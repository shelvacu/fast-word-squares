require "sqlite3"
stats_fn = (ARGV[0]? || "db.sqlite")

DB.open "sqlite3://./#{stats_fn}" do |db|
  num_finished = db.query_one("SELECT COUNT(*) FROM work_pieces WHERE finished_at NOT NULL", as: Int32)
  num_total =    db.query_one("SELECT COUNT(*) FROM work_pieces", as: Int32)
  ratio_done = num_finished.to_f / num_total
  #ratio_done = db.query_one("SELECT (SELECT COUNT(*) FROM work_pieces WHERE finished_at NOT NULL)*1.0 / (SELECT COUNT(*) FROM work_pieces);", as: Float64)
  puts "#{num_finished}/#{num_total} work pieces finished."
  puts "~%.2f%% done." % (ratio_done*100)

  last_piece_alloc = db.query_one("SELECT work FROM work_pieces WHERE work_start NOT NULL ORDER BY work_start DESC LIMIT 1", as: String)
  last_piece_finished = db.query_one("SELECT work FROM work_pieces WHERE finished_at NOT NULL ORDER BY finished_at DESC LIMIT 1", as: String)
  puts "Most recently allocated work piece: #{last_piece_alloc}"
  puts "Most recently finished  work piece: #{last_piece_finished}"

  start_time = db.query_one("SELECT work_start FROM work_pieces WHERE work_start NOT NULL ORDER BY work_start ASC LIMIT 1", as: Time)
  puts "started at #{start_time}"
  num_remaining = num_total - num_finished
  puts "#{num_remaining} work pieces remaining"
  elapsed = Time.utc_now - start_time
  puts "elapsed time is #{elapsed}"
  rate = num_finished/elapsed.ticks.to_f
  #puts "finishing #{rate} work pieces per tick"
  remaining_ticks = (num_remaining/rate).to_i64
  #puts "#{remaining_ticks} ticks remaining"
  remaining_span = Time::Span.new(remaining_ticks)
  puts remaining_span
end
