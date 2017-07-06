require "sqlite3"

unless ARGV.length == 2 || ARGV.length == 4
  STDERR.puts "need two or four arguments, word list and word length, optionally start length and compute binary location"
  exit 1
end

wordlist_fn = ARGV[0]
word_len = ARGV[1].to_i

if ARGV.length == 2
  start_len = word_len
  compute_exec = ""
else
  start_len = ARGV[2].to_i
  compute_exec = ARGV[3]
end

DB.open "sqlite://./db.sqlite" do |db|
  db.exec(
    "CREATE TABLE words ( word CHAR(?) UNIQUE NOT NULL )",
    word_len
  )
  skipped_words = 0
  db.transaction do
    File.read(wordlist_fn).split.map(&.downcase).each do |word|
      if word.size != word_len
        next
      end
      if word.chars.any?{|c| !('a'..'z').includes?(c)}
        skipped_words += 1
        next
      end

      db.exec(
        "INSERT OR IGNORE INTO words (word) VALUES (?)",
        word
      )
    end
    puts "#{skipped_words} skipped because of invalid characters (not a-z)"
  end

  db.exec(
    "CREATE TABLE work_pieces ( "+
    " finished_at CHAR(23),"+ #format: "YYYY-MM-DD HH:MM:SS.SSS"
    " assigned_ip VARCHAR(45),"+ #45 chars is max length of textual IP addr https://stackoverflow.com/questions/166132/maximum-length-of-the-textual-representation-of-an-ipv6-address
    " last_progress CHAR(23),"+
    " work_start CHAR(23),"+
    " work CHAR(?) UNIQUE NOT NULL,"
    " finder_uuid CHAR(36)"
    ")", start_len
  )
  if start_len == word_len
    db.exec(
      "INSERT OR IGNORE INTO work_pieces (work) SELECT word FROM words"
    )
  else
    Process.run(
      compute_exec,
      [
        "-w", wordlist_fn,
        "-a", word_len,
        "-f", start_len
      ],
      output : true,
      error : STDERR
    ) do |proc|
      db.transaction do
        proc.output.each_line do |line|
          work = line.split(" / ")[0].chars.reject{|c| c == '*' || c == '-'}.join
          db.exec(
            "INSERT OR IGNORE INTO work_pieces (work) VALUES (?)"
            work
          )
        end
      end
    end
  end
end

db.exec(
  "CREATE INDEX im-no-good-at-naming-things ON work_pieces (assigned_ip, last_progress, finished_at);"+
  "CREATE INDEX ingath2 ON work_pieces (finder_uuid);"+
  "CREATE TABLE results ( result VARCHAR(255) );"+
  "CREATE TABLE options ( word_length INT )"
)

db.exec(
  "INSERT INTO options (word_length) VALUES (?)"
  word_len
)
