require "socket"
require "json"
require "logger"
require "secure_random"
require "sqlite3"
require "./word-square/version"
require "./word-square/word-square-packet"

log_fh = File.open("word-square-server.log","a")

logger = Logger.new(IO::MultiWriter.new(log_fh, STDERR, sync_close: true))
logger.level = Logger::DEBUG

logger.info("Starting server")

DB.open "sqlite3://./db.sqlite" do |db|
  word_len = db.query_one("SELECT word_length FROM options", as: Int32).to_u8
  serv = TCPServer.new("0.0.0.0", 45999)

  while cli = serv.accept
    spawn do
      ip = cli.remote_address.address
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
          work_id, results = WordSquarePacket.read_results(data)
          logger.debug("Got results, work #{work_id} length #{results.size}")
          db.transaction do
            results.each do |res|
              db.exec(
                # TODO: Add ON CONFLICT or whatever it's called.
                "INSERT INTO results (result) VALUES (?)",
                res
              )
            end
          end
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
    end
  end
end
