require 'open3'
require 'json'
require 'sequel'

raise "need two arguments, word list and word length, optionally start length and compute binary location" unless ARGV.length == 2 || ARGV.length == 3

word_len = ARGV[1].to_i
start_len = (ARGV[2] || word_len).to_i
raise "word length must be a number greater than zero" if word_len <= 0
raise "start length must be greater or equal to word length" if start_len < word_len
words = File.read(ARGV[0]).scrub.split("\n").map(&:downcase).find_all{|w| w.length == word_len && w.chars.all?{|c| ('a'..'z').include?(c)}}

DB = Sequel.sqlite("main.db")

DB.create_table :words do
  TrueClass :finished, null: false, default: false
  String :assigned_to
  Time :last_progress
  Time :work_start
  String :word
  String :finder_uuid

  add_index :update_uuid
end

if start_len == word_len
  DB[:words].import([:word], words.map{|w| [w]})
else
  bla = File.absolute_path(ARGV[3])
  raise unless File.exist?(bla)
  DB.transaction do
    stdin, stdout, stderr, thr = Open3.popen3(
                             bla,
                             "-w", ARGV[0],
                             "-f", "#{start_len/word_len},#{start_len%word_len}"
                           )
    stdin.close
    Thread.new do
      IO.copy_stream stderr, STDERR
    end
    while line = stdout.gets
      s = line.split(" / ")[0].chars.find_all{|c| (?a..?z).include? c}.join
      DB[:words].insert(word: s)
    end
  end
end
    

DB.add_index :words, [:assigned_to, :word]

DB.create_table :results do
  String :result
end

DB.create_table :options do
  String :options
end

DB[:options].insert(options: {square_size: word_len}.to_json)
