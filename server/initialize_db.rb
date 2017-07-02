require 'sequel'

raise "need two arguments, word list and word length" unless ARGV.length == 2

word_len = ARGV[1].to_i
raise "word length must be a number greater than zero" if word_len <= 0
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

DB[:words].import([:word], words.map{|w| [w]})

DB.add_index :words, [:assigned_to, :word]

DB.create_table :results do
  String :result
end
