require "json"
require "../word-square/version"

module WordSquarePacket
  class InvalidPacket < Exception
  end
  
  enum PacketType : UInt8
    # Sent from the server to the client.
    # Data is json of the wordlist, word length, and server src location to comply with AGPL
    Start
    
    # Sent from client to server to request work.
    # No data.
    WorkRequest
    
    # Sent from server to client in response to a WorkRequest.
    # Data: The start string, to be passed to the --start parameter of the compute process
    Work
    
    # Sent from client to server when some results have been generated.
    # Data: The start string given in Work packet
    # Data: Array of strings, representing the results
    ResultsPartial
    
    # Same as ResultsPartial, but indicates that this is the end of the results for this Work.
    ResultsFinish
  end
  
  def self.read_pkt(io : IO)
    ptype_i = io.read_byte
    if ptype_i.nil?
      raise InvalidPacket.new("Could not read from IO")
    else
      pkt_type = PacketType.new(ptype_i)
      data_len = io.read_bytes(UInt32, IO::ByteFormat::NetworkEndian)
      data = Bytes.new(data_len)
      io.read_fully(data)
      return {pkt_type, data}
    end
  end
  
  def self.write_pkt(io : IO, pkt_type : PacketType, data : Bytes) : Nil
    io.write_byte pkt_type.value
    io.write_bytes(data.size.to_u32, IO::ByteFormat::NetworkEndian)
    io.write(data)
  end
  
  def self.read_start(data : Bytes)
    parsed = JSON.parse(String.new(data))
    return {
      wordlist: parsed["wordlist"].as_a.map{|v| v.as(String)},
      word_len: parsed["word_len"].as_i.to_u8,
      server_ver: parsed["server_ver"].as_s,
      server_src: parsed["server_src"].as_s
    }
  end
  
  def self.write_start(wordlist : Array(String), word_len : UInt8, server_ver : String, server_src : String)
    {
      "wordlist" => wordlist,
      "word_len" => word_len,
      "server_ver" => server_ver,
      "server_src" => server_src
    }.to_json.to_slice
  end
  
  def self.read_work(data : Bytes)
    String.new(data)
  end
  
  def self.write_work(work : String)
    work.to_slice
  end
  
  def self.read_results(data : Bytes) : {String, Array(String)}
    work_id_len = data[0]
    work_id = data[1, work_id_len]
    rest = data + (work_id_len + 1)
    result_length = rest[0] #The length of each result
    result_data = rest + 1
    raise InvalidPacket.new("The length of the result data is not a multiple of result_length") if result_length != 0 && result_data.size % result_length != 0
    if result_length == 0
      results = [] of String
    else
      results = result_data.each_slice(result_length).map(&.map(&.chr).join)
    end
    return String.new(work_id), results.to_a
  end
  
  def self.write_results(work_id : String, results : Array(String))
    joined_results = results.join
    if results.size == 0
      each_res_len = 0
    else
      each_res_len = results.first.size
    end
    if results.size != 0 && each_res_len * results.size != joined_results.size
      raise ArgumentError.new("All results must be the same length")
    end
    res = Bytes.new(2 + work_id.size + joined_results.size)
    raise ArgumentError.new("work id and each result must be less than 255 chars") unless work_id.size <= UInt8::MAX && each_res_len <= UInt8::MAX
    res[0] = work_id.size.to_u8
    (res + 1).copy_from work_id.to_slice
    left = res + (work_id.size + 1)
    left[0] = each_res_len.to_u8
    (left + 1).copy_from joined_results.to_slice
    return res
  end
end
