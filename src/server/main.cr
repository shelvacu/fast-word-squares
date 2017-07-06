require "socket"
require "json"
require "sqlite3"
require "../word-square/version"
require "../word-square/word-square-packet"

logger = Logger.new("word-square-server.log")

logger.info("Starting server")

DB.open "sqlite://./db.sqlite" do |db|
  word_len = db.query_one("SELECT word_length FROM opts", as : Int32)
  serv = TCPServer.new("0.0.0.0", 45999)

  while cli = serv.accept?
    spawn do
      ip = cli.remote_address.address
      wl = db.query_all("SELECT word FROM words", as: String)
      data = WordSquarePacket.write_start(
        wordlist : wl,
        word_len : word_len,
        server_ver : "Shelvacu's word square work split server #{WordSquare::Version}",
        server_src : "https://github.com/shelvacu/fast-word-squares"
      )
      WordSquarePacket.write_pkt(cli, WordSquarePacket::PacketType::Start, data)

      loop do
        ptype, data = WordSquarePacket.read_pkt(cli)
        case ptype
        when WordSquarePacket::PacketType::WorkRequest
          # This is called the finder_uuid because it's a uuid that allows us to find what
          # record what updated after we've done so
          finder_uuid = SecureRandom.uuid
          now = Time.utc_now
          res = db.exec(
            "UPDATE work_pieces "+
            "SET last_assigned_to=?, work_start=?, last_progress=?, finder_uuid=? "+
            "WHERE rowid IN ("+
            " SELECT rowid "+
            " FROM words "+
            " WHERE finished_at IS NULL "+
            " ORDER_BY (last_assigned_to IS NULL) DESC, last_progress ASC "+
            " LIMIT 1 "+
            ")",
            ip, now, now, finder_uuid
          )
          if res.rows_affected != 1
            logger.warn(
              "#{ip}: Expected to affect exactly one row, but affected #{res.rows_affected} rows"
            )
            cli.close
            break
          end
          new_work = db.query_one("SELECT work FROM work_pieces WHERE finder_uuid=?", finder_uuid, as : String)
          WordSquarePacket.write_pkt(cli, WordSquarePacket::PacketType::Work, new_work.to_slice)
        when WordSquarePacket::PacketType::ResultsPartial, WordSquarePacket::PacketType::ResultsFinish
          work_id, results = WordSquarePacket.read_results(data)
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
