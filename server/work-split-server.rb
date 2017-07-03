require 'securerandom'
require 'socket'
require 'json'
require 'logger'
require 'sequel'

Thread.abort_on_exception = true

$logger = Logger.new("work-split-server.log")

$logger.info("Starting work split server")

DB = Sequel.sqlite("main.db")
#create tables and stuff

def disconn(ip)
  $logger.info("Disconnect from #{ip}")
  DB[:words].where(finished: false, assigned_to: ip).update(assigned_to: nil)
end

serv = TCPServer.new("0.0.0.0", 45999)
puts "Server is running"
while cli = serv.accept
  Thread.new(cli) do |cli|
    ip = cli.remote_address.ip_address
    $logger.info("New connection from #{ip}")
    cli.puts({
               type: 'wordlist',
               words: DB[:words].map(:word),
               server_source_location: "https://github.com/shelvacu/fast-word-squares"
             }.to_json)
    
    while true
      begin
        line = cli.gets
      rescue IOError
        disconn(ip)
        break
      end
      if line.nil?
        disconn(ip)
        break
      end
        
      stuff = JSON.parse line
      debug_line = line.dup
      #would make the log *very* big if this wasn't done.
      if debug_line.has_key? 'results'
        debug_line['results'] = '...omitted...'
      end
      $logger.debug "Received from #{ip}: #{debug_line.dump}"
      case stuff['type']
      when 'work_request'
        pieces = (stuff['pieces'] || 1).to_i
        if pieces <= 0
          $logger.warn("Invalid piece count #{pieces}, skipping")
          next
        end

        work = []
        pieces.times do
          update_id = SecureRandom.uuid
          now = Time.now.utc
          to_update = DB[
            "SELECT rowid "+
            "FROM words "+
            "WHERE finished = 0 "+
            #"AND ("+
            #" assigned_to IS NULL "+
            #" OR last_progress <= ? "+
            #" OR work_start <= ?) "+
            "ORDER BY (assigned_to IS NULL) DESC, work_start ASC"+ 
            "LIMIT 1"]
          num_updated = DB[:words]
            .where(rowid: to_update)
            .update(assigned_to: ip, last_progress: now, work_start: now, finder_uuid: update_id)
          break if num_updated == 0
          new_word = DB[:words].where(finder_uuid: update_id).get(:word)
          if new_word.nil?
            $logger.warn("This shouldn't happen")
            break
          end
          work << new_word
        end

        res = {type: 'work', pieces: work}.to_json
        begin
          cli.puts(res)
        rescue IOError, Errno::EPIPE
          disconn(ip)
          break
        end
      when 'work_update'
        word = stuff['word']
        DB[:words].where(word: word, assigned_to: ip).update(last_progress: Time.now.utc)
      when 'work_finish'
        DB.transaction do
          num_upd = DB[:words].where(word: stuff['word']).update(finished: true)
          if num_upd == 0
            $logger.warn("work_finish was sent, but work does not correspond to entry in DB, ignoring...")
            raise Sequel::Rollback
          end
          DB[:results].import([:result], stuff['results'].map{|r| [r]}, commit_every: false)
        end
      else
        $logger.warn("Unrecognized type, stuff was #{stuff.inspect}")
      end
    end
  end
end
