require "sqlite3"

unless ARGV.size == 2 || ARGV.size == 4
  STDERR.puts "need two or four arguments, word list and word length, optionally start length and compute binary location"
  exit 1
end

wordlist_fn = ARGV[0]
word_len = ARGV[1].to_i

if ARGV.size == 2
  start_len = word_len
  compute_exec = ""
else
  start_len = ARGV[2].to_i
  compute_exec = ARGV[3]
end

DB.open "sqlite3://./db.sqlite" do |db|
  # We're initializing the DB, so if it gets corrupted that's fine
  db.exec("PRAGMA synchronous = OFF")
  #db.exec("PRAGMA journal_mode = MEMORY")

  db.exec(
    "CREATE TABLE words ( word CHAR(#{word_len}) UNIQUE NOT NULL )"
  )
  skipped_words = 0
  db.transaction do
    prepped_stmt = db.build("INSERT OR IGNORE INTO words (word) VALUES (?)"+ ",(?)"*99)
    puts "Reading and splitting #{wordlist_fn}"
    words = File.read(wordlist_fn).split.map(&.downcase)
    words.reject! do |word|
      word.size != word_len || word.chars.any?{|c| !('a'..'z').includes?(c)}
    end
    puts "Populating table words from wordlist #{wordlist_fn} with #{words.size} words"
    words.each_slice(100, reuse: true) do |slice|
      #if i % 100 == 0
      #  print "\b\b\b\b\b\b\b"
      #  print "%.2f%%" % (i.to_f / words.size)
      #end

      #if word.size != word_len
      #  next
      #end
      #if word.chars.any?{|c| !('a'..'z').includes?(c)}
      #  skipped_words += 1
      #  next
      #end

      if slice.size == 100
        prepped_stmt.exec(slice)
      else
        db.exec(
          ("INSERT OR IGNORE INTO words (word) VALUES (?)"+ ",(?)"*(slice.size-1)),
          slice
        )
      end
    end
    puts "Finished."
    #puts "#{skipped_words} skipped because of invalid characters (not a-z)"
  end
  
  db.exec(
    "CREATE TABLE work_pieces ( "+
    " finished_at CHAR(23),"+ #format: "YYYY-MM-DD HH:MM:SS.SSS"
    " assigned_ip VARCHAR(45),"+ #45 chars is max length of textual IP addr https://stackoverflow.com/questions/166132/maximum-length-of-the-textual-representation-of-an-ipv6-address
    " last_progress CHAR(23),"+
    " work_start CHAR(23),"+
    " work CHAR(#{start_len}) NOT NULL,"+
    " finder_uuid CHAR(36)"+
    ")"
  )
  if start_len == word_len
    puts "Populating work_pieces table directly from words table"
    db.exec(
      "INSERT OR IGNORE INTO work_pieces (work) SELECT word FROM words"
    )
  else
    puts "Running compute process to populate work_pieces table"
    args =
      [
        "-w", wordlist_fn,
        "-a", word_len.to_s,
        "-f", start_len.to_s
      ]
    puts "#{compute_exec.inspect} #{args.inspect}"
    Process.run(
      compute_exec,
      args,
      output: nil,
      error: true
    ) do |proc|
      db.transaction do
        slice_size = 250_000 # this is the absolute max, any higher and sqlite complains
        prepped_stmt = db.build("INSERT INTO work_pieces (work) VALUES (?)"+(",(?)"*(slice_size-1)))
        proc.output.each_line.each_slice(slice_size, reuse: true) do |slice|
          works = slice.map(&.split(" / ")[0].chars.reject{|c| c == '*' || c == '-'}.join)
          if works.size == slice_size
            prepped_stmt.exec(works)
          else
            db.exec(
              "INSERT INTO work_pieces (work) VALUES (?)"+(",(?)"*(works.size-1)),
              works
            )
          end
        end
      end
    end
    puts "Finished"
  end

  puts "Creating indexes"
  #db.exec(
  #  "CREATE INDEX im_no_good_at_naming_things ON work_pieces (finished_at, assigned_ip, last_progress);"
  #)
  db.exec(
    # This index was determined through much trial and error. I do not understand why the ASC and DESC are needed, but they are.
    "CREATE INDEX finass110 ON work_pieces (finished_at ASC, assigned_ip IS NULL ASC, last_progress DESC);"
  )
  db.exec(
    "CREATE INDEX ingant2 ON work_pieces (finder_uuid);"
  )
  db.exec(
    "CREATE TABLE results ( result VARCHAR(255) );"
  )
  db.exec(
    "CREATE TABLE options ( word_length INT )"
  )

  db.exec(
    "INSERT INTO options (word_length) VALUES (?)",
    word_len
  )

  puts "Finished."
end

