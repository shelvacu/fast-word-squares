require "socket"
require "json"
require "sqlite3"

logger = Logger.new("word-square-server.log")

logger.info("Starting server")

DB.open "sqlite://./db.sqlite" do |db|
  serv = TCPServer.new("0.0.0.0", 45999)
  
end
