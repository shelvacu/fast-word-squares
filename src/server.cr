require "socket"
require "option_parser"
require "gzip"
require "json"
require "logger"
require "secure_random"
require "sqlite3"
require "./word-square/version"
require "./word-square/word-square-packet"

lib LibC
  fun fsync(fd : LibC::Int) : LibC::Int
end

database_short_fn = "./db.sqlite"
datadir = "."

OptionParser.parse! do |pr|
  pr.on("-b FILE","--database-file FILE","Name of the database file to use, relative to the --data-folder") do |fn|
    database_short_fn = fn
  end
  pr.on("-f FOLDER", "--data-folder FOLDER", "Path to the directory to store database, log, and results") do |folder|
    datadir = folder
  end
  pr.on("-v","--version","Display version information"){puts WordSquare::VERSION; exit 0}
  pr.on("-h","--help", "Display this help message"){puts pr; exit 0}
end

datadir = File.expand_path(datadir)
database_fn = File.join(datadir, database_short_fn)
log_fn = File.join(datadir, "word-square-server.log")
res_fn = File.join(datadir, "results.txt")

log_fh = File.open(log_fn,"a")
res_fh = File.open(res_fn,"a")
res_mutex = Mutex.new

#if the results file was closed uncleanly, it may not end with a newline. This makes sure that it does.
res_fh.puts

logger = Logger.new(IO::MultiWriter.new(log_fh, STDERR, sync_close: true))
logger.level = Logger::DEBUG

logger.info "Starting server"

word_len = 0_u8

full_db_uri = "sqlite3://#{database_fn}"

logger.info "Using datadir #{datadir}, logging to #{log_fn}, outputting results to #{res_fn}, using sqlite3 database #{full_db_uri}"

DB.open full_db_uri do |db|
  word_len = db.query_one("SELECT word_length FROM options", as: Int32).to_u8
end

if word_len == 0
  logger.fatal "this aint supposed to happen"
  exit 1
end

serv = TCPServer.new("0.0.0.0", 45999)

def prep_stmt(plain_db,stmt)
  check LibSQLite3.prepare_v2(plain_db, stmt, stmt.size+1, out prep_stmt, nil)
  return prep_stmt
end

macro check(i)
  %res = {{i}}
  if %res != 0
    raise "raw sqlite3 func call failed err code #{%res} err string: #{String.new(LibSQLite3.errmsg(plain_db))}"
  end
end

lib LibSQLite3
  fun errmsg = sqlite3_errmsg(db : SQLite3) : Pointer(LibC::Char)
  fun exec = sqlite3_exec(db : SQLite3, stmt_str : UInt8*, callback : {Void*, LibC::Int, UInt8**, UInt8**} ->, Void*, errmsg : UInt8**) : Int32
end

while tcli = serv.accept
  spawn do
    start_time : Time = Time.now
    stop_time  : Time = Time.now

    cli = tcli
    ip = cli.remote_address.address
    puts "aaa"
    #check LibSQLite3.open_v2(File.expand_path(database_fn), out plain_db, SQLite3::Flag::READWRITE, nil)
    puts "aa"
    #insert_stmt = prep_stmt(plain_db, "INSERT INTO results (result) VALUES (?)")
    puts "ab"
    #begin_trans = prep_stmt(plain_db, "BEGIN")
    #puts "ac"
    #commit_trans= prep_stmt(plain_db, "COMMIT")
    #puts "a"
    db = DB.open full_db_uri
    begin
      #DB.open full_db_uri do |db|
      wl = db.query_all("SELECT word FROM words", as: String)
      data = WordSquarePacket.write_start(
        wordlist: wl,
        word_len: word_len,
        server_ver: "Shelvacu's word square work split server #{WordSquare::VERSION}",
        server_src: "https://github.com/shelvacu/fast-word-squares"
      )
      WordSquarePacket.write_pkt(cli, WordSquarePacket::PacketType::Start, data)

      loop do
        Fiber.yield
        ptype, data = WordSquarePacket.read_pkt(cli)
        case ptype
        when WordSquarePacket::PacketType::WorkRequest
          # This is called the finder_uuid because it's a uuid that allows us to find what
          # record what updated after we've done so
          finder_uuid = SecureRandom.uuid
          now = Time.utc_now
          logger.debug("Finding a work piece")
          res = db.exec(
            "UPDATE work_pieces "+
            "SET assigned_ip=?, work_start=?, last_progress=?, finder_uuid=? "+
            "WHERE rowid IN ("+
            " SELECT rowid "+
            " FROM work_pieces "+
            " WHERE finished_at IS NULL "+
            " ORDER BY (assigned_ip IS NULL) DESC, last_progress ASC "+
            " LIMIT 1 "+
            ")",
            ip, now, now, finder_uuid
          )
          logger.debug("Updated a thing, took #{Time.utc_now - now}")
          if res.rows_affected != 1
            logger.warn(
              "#{ip}: Expected to affect exactly one row, but affected #{res.rows_affected} rows"
            )
            cli.close
            break
          end
          new_work = db.query_one("SELECT work FROM work_pieces WHERE finder_uuid=?", finder_uuid, as: String)
          logger.info("Sending work #{new_work} to #{ip}")
          WordSquarePacket.write_pkt(cli, WordSquarePacket::PacketType::Work, new_work.to_slice)
        when WordSquarePacket::PacketType::ResultsPartial, WordSquarePacket::PacketType::ResultsFinish
          read_results_start = Time.now
          work_id, results = WordSquarePacket.read_results(data)
          read_results_ms = (Time.now - read_results_start).total_milliseconds
          ##logger.debug("read_results took ".rjust(30) + .to_s)
          ##logger.debug("Got results, work #{work_id} length #{results.size}")
          #result_count_before = db.scalar("SELECT COUNT(*) FROM results")
          #logger.debug("Result count is #{result_count_before}")
          start_time = Time.now
          non_inserting_ms = (start_time - stop_time).total_milliseconds
          ##logger.debug("non-inserting time is ".rjust(30) + .to_s)
          #check LibSQLite3.exec(plain_db, "BEGIN", nil, nil, nil)
          res_mutex.synchronize do
            #Gzip::Writer.open(res_fh) do |gzip_io|
              results.each do |res_text|
                #check LibSQLite3.bind_text(insert_stmt, 1, res_text, res_text.bytesize, nil)
                #res = LibSQLite3.step(insert_stmt)
                #raise "bad" unless res == 101
                #check LibSQLite3.reset(insert_stmt)
                #db.exec("INSERT INTO results (result) VALUES (?)"+(",(?)"*(slice.size-1)),slice)
                res_fh.puts res_text
              end
            #end
            res_fh.flush
            LibC.fsync(res_fh.fd)
          end
          #check LibSQLite3.exec(plain_db, "COMMIT", nil, nil, nil)
          stop_time = Time.now
          #result_count_after = db.scalar("SELECT COUNT(*) FROM results")
          time_taken_for_insert = (stop_time - start_time)
          ##logger.debug("insert took ".rjust(30)+time_taken_for_insert.to_s)
          inserts_per_second = (results.size / time_taken_for_insert.total_seconds).to_i
          logger.info("non-insert %.3f; readres %.3f; insert %.3f; ips %d; count %d" % {non_inserting_ms, read_results_ms, time_taken_for_insert.total_milliseconds, inserts_per_second, results.size})
          ##logger.debug(.to_i.to_s + " inserts/s")
          #if result_count_before == result_count_after && results.size > 0
          #  logger.warn("Result counts before and after insertion were the same :(")
          #end
          if ptype == WordSquarePacket::PacketType::ResultsFinish
            logger.debug("Setting finished on #{work_id}")
            db.exec(
              "UPDATE work_pieces SET finished_at=? WHERE work=?",
              Time.utc_now, work_id
            )
          end
        else
          logger.warn("Encountered unhandled packet type #{ptype}")
        end
      end
    rescue e : SQLite3::Exception
      puts e.inspect_with_backtrace
      cli.close
    ensure
      #LibSQLite3.finalize(begin_trans)
      #LibSQLite3.finalize(commit_trans)
      #LibSQLite3.finalize(insert_stmt)
      #LibSQLite3.close_v2(plain_db)
      db.close
    end
  end
end
