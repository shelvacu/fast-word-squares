require 'open3'
require 'socket'
require 'json'

Thread.abort_on_exception = true

raise "Need server name/ip, path to compute executable, and number of threads" unless ARGV.size == 3
$compute_exec = ARGV[1]
$num_threads = ARGV[2].to_i
puts "Will connect to server #{ARGV[0]}, and use the executable located at the path #{$compute_exec} for computation. Thread pool size is #{$num_threads}"

$threads_to_make = $num_threads
$wordlist_fn = `mktemp wordsquare-wordlist-tmpfile-XXXXXXX.txt`.chomp

class WorkUnit
  def initialize(word)
    @word = word
    @last_update = Time.now
    @result = ""
  end

  def run
    args = [
      $compute_exec,
      "-w", $wordlist_fn,
      "-a", $word_len.to_s,
      "-s", @word
    ]
    p args
    stdout, stderr, status = Open3.capture3(*args)
    STDERR.print stderr
    if status.success?
      $conn.puts({type: 'work_finish', word: @word, results: stdout.split("\n")}.to_json)
    else
      STDERR.puts "compute failed for word #{@word} :("
    end
  end
end


puts "Connecting"
$conn = TCPSocket.new(ARGV[0], 45999)
puts "Connected"
line = JSON.parse($conn.gets)
raise unless line['type'] == 'wordlist'
puts "Got wordlist, first word is #{line['words'].first}"
$word_len = line['words'].first.size
File.open($wordlist_fn, 'wt') do |fn|
  line['words'].each do |word|
    fn.puts word
  end
end
puts "Wrote wordlist"
Thread.new do
  while true
    if $threads_to_make > 0
      $conn.puts({type: 'work_request', pieces: 1}.to_json)
      sleep 0.1
    else
      sleep 1
    end
  end
end
puts "starting read loop"
while bare_line = $conn.gets
  puts "read line"
  line = JSON.parse(bare_line)
  raise if line['pieces'].size != 1
  puts "Starting new workunit"
  wu = WorkUnit.new(line['pieces'].first)
  Thread.new do
    wu.run
    puts "Finished workunit"
    $threads_to_make += 1
  end
  $threads_to_make -= 1
end

