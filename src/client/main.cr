require "socket"
require "../word-square/word-square-packet"

thread_pool = [] of Fiber
work_chan = Channel(String).new

raise "Need server name/ip, path to compute executable, and number of threads" unless ARGV.size == 3

num_threads = ARGV[2].to_i

puts "Will connect to #{ARGV[0]}, and use the compute executable #{ARGV[1]}. Will create #{num_threads} processes."

conn = TCPSocket.new(ARGV[0], 45999)
print "Connected"

ptype, data = WordSquarePacket.read_pkt(conn)
if ptype != WordSquarePacket::PacketType::Start
  STDERR.puts "Unexpected response from server!"
  exit 1
end

start = WordSquarePacket.read_start(data)

puts " to #{start[:server_ver]}"

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

    work_chan.send word
  end
end

write_chan = Channel({WordSquarePacket::PacketType, Bytes}).new(32)

write_thread = spawn do
  loop do
    ptype, data = write_chain.receive
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

    Process.run(
      ARGV[1],
      [
        "-w", wordlist_fn,
        "-a", start['word_len'],
        "-s", start_word
      ],
      shell : false,
      output : true, #allocate an fn to read STDOUT
      error : STDERR #pipe STDERR from the internal process to this process
    ) do |proc|
      proc.output.each_line.each_slice(1000) do |results|
        bytes = WordSquarePacket.write_results(start_word, results)
        write_chan.send({WordSquarePacket::PacketType::ResultsPartial})
      end

      # Tell the server we've finished sending it data.
      bytes = WordSquarePacket.write_results(start_word, [] of String)
      write_chan.send({WordSquarePacket::PacketType::ResultsFinish, bytes})
    end

    # We're done, signal that another thread & process should be started

    start_chan.send nil
  end
end
  
