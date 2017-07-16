require "socket"
require "option_parser"
require "./word-square/word-square-packet"

compute_exec = ""
server_addr  = ""
num_threads  = System.cpu_count * 2

parser = 
OptionParser.parse! do |pr|
  pr.banner = "Usage: #{$0} [arguments] server_address"
  #pr.on("-s SERV", "--server SERV", "The name or ip address of the server to connect to.")
  pr.on("-c EXEC", "--compute-exec EXEC", "The path to the executable to use for compute. Will try to determine automatically if not specified.") do |exec_path|
    compute_exec = exec_path
  end
  pr.on("-t THREADS","--threads THREADS", "The number of concurrent processes to run. Defaults to two times the number of logical processors.") do |t|
    t = t.to_i
    if t <= 0
      STDERR.puts "Invalid number of cores: #{t}"
      exit 1
    end
    num_threads = t
  end
  pr.on("-h","--help", "Print this help message"){STDERR.puts pr;exit 0}
  pr.unknown_args do |args|
    if args.size != 1
      STDERR.puts "Expected exactly one (non-dash) argument, got #{args.size} arguments."
      exit 1
    end
    server_addr = args.first
  end
end
if server_addr == ""
  STDERR.puts parser
  exit 1
end

thread_pool = [] of Fiber
work_chan = Channel(String).new

#TODO: correct this message.
puts "Will connect to #{server_addr}, and create #{num_threads} processes."
if compute_exec == ""
  puts "Determining compute exec path automatically"
else
  puts "Using compute executable at #{File.expand_path(compute_exec)}"
end

conn = TCPSocket.new(server_addr, 45999)
puts "Connected"

ptype, data = WordSquarePacket.read_pkt(conn)
if ptype != WordSquarePacket::PacketType::Start
  STDERR.puts "Unexpected response from server!"
  exit 1
end

#puts data[0,20]

start = WordSquarePacket.read_start(data)

puts " to #{start[:server_ver]}"

if compute_exec == ""
  guess_compute_path = File.join(File.dirname($0), "compute-o#{start["word_len"]}")
  if File.executable?(guess_compute_path) # Will also test existance.
    compute_exec = guess_compute_path
    puts "Using compute executable #{compute_exec}"
  else
    STDERR.puts "Could not locate a compute executable of order #{start["word_len"]}"
    exit 1
  end
end

wordlist_fn = `mktemp --tmpdir word-square-wordlist-tmp.XXXXXXXXXX`.chomp

File.write(wordlist_fn, start[:wordlist].join("\n"))

read_thread = spawn do
  loop do
    ptype, data = WordSquarePacket.read_pkt(conn)
    if ptype != WordSquarePacket::PacketType::Work
      STDERR.puts "Unexpected response from server!"
      exit 1
    end

    work = WordSquarePacket.read_work(data)

    puts "Recieved work #{work}"
    
    work_chan.send work
  end
end

write_chan = Channel({WordSquarePacket::PacketType, Bytes}).new(32)

write_thread = spawn do
  loop do
    ptype, data = write_chan.receive
    WordSquarePacket.write_pkt(conn, ptype, data)
  end
end

start_chan = Channel(Nil).new

spawn do
  num_threads.times do
    start_chan.send nil
  end
end

loop do
  start_chan.receive

  write_chan.send({WordSquarePacket::PacketType::WorkRequest, Bytes.new(0)})
  
  spawn do
    start_word = work_chan.receive

    puts "Starting work on #{start_word}"
    args =
      [
        "-w", wordlist_fn,
        "-a", start["word_len"].to_s,
        "-s", start_word
      ]
    puts "#{compute_exec.inspect} #{args.inspect}"
    Process.run(
      compute_exec,
      args,
      shell: false,
      output: nil, #allocate an fn to read STDOUT
      error: true #pipe STDERR from the internal process to this process
    ) do |proc|
      Fiber.yield
      proc.output.each_line.each_slice(10_000, reuse: true) do |results|
        #puts "Writing to socket #{results.size} results for #{start_word}"
        bytes = WordSquarePacket.write_results(start_word, results)
        write_chan.send({WordSquarePacket::PacketType::ResultsPartial, bytes})
        Fiber.yield
      end

      puts "Finished #{start_word}"
      # Tell the server we've finished sending it data.
      bytes = WordSquarePacket.write_results(start_word, [] of String)
      write_chan.send({WordSquarePacket::PacketType::ResultsFinish, bytes})
    end

    # We're done, signal that another thread & process should be started

    start_chan.send nil
  end
end
