require 'json'

module WordSquarePacket
  class InvalidPacket < Error
  end

  enum PacketType : UInt8
    Start
    Work
    WorkRequest
    Results
  end
  
  def self.read_pkt(io : IO)
    pkt_type = PacketType.new(io.read_byte)
    data_len = io.read_bytes(UInt32, IO::ByteFormat::NetworkEndian)
    data = Bytes.new(data_len)
    io.read_fully(data)
    return {pkt_type, data}
  end

  def self.write_pkt(io : IO, pkt_type : PacketType, data : Bytes) : Nil
    io.write_byte pkt_type.value
    io.write_bytes(data.size.to_u32, IO::ByteFormat::NetworkEndian)
    io.write(data)
  end
  
  def self.read_start(data : Bytes | String)
    parsed = JSON.parse(data.to_s)
    return {
      wordlist: parsed["wordlist"].as_a.map{|v| v.as_s},
      word_len: parsed["word_len"].as_u8,
      server_src: parsed["server_src"].as_s
    }
  end

  def self.write_start(wordlist : Array(String), word_len : UInt8, server_src : String)
    {
      "wordlist" => wordlist,
      "word_len" => word_len,
      "server_src" => server_src
    }.to_json
  end

  def self.read_work(data : Bytes)
    data.to_s
  end

  def self.write_work(work : String)
    work.to_slice
  end

  def self.read_results(data : Bytes)
    work_id_len = data[0]
    word_id = data[1, work_id_len]
    rest = data + (work_id_len + 1)
    result_length = rest[0] #The length of each result
    result_data = rest + 1
    raise InvalidPacket.new("The length of the result data is not a multiple of result_length") unless result_data.size % result_length == 0
    return result_data.each_slice(result_length).map(&.map(&.chr).join)
  end

  def self.write_results(work_id : String, results : Array(String))
    joined_results = results.join
    if results.first.size * results.size != joined_results.size
      raise ArgumentError.new("All results must be the same length")
    end
    res = Bytes.new(2 + word_id.size + joined_results.size)
    raise ArgumentError.new("work id and each result must be less than 255 chars") unless work_id.size <= UInt8::MAX && results.first.size <= UInt8::MAX
    res[0] = work_id.size.to_u8
    (res + 1).copy_from work_id.to_slice
    left = res + (word_id.size + 1)
    left[0] = results.first.size.to_u8
    (left + 1).copy_from joined_results.to_slice
    return res
  end
end
