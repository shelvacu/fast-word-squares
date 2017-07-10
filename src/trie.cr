#class TrieIndex
#  @root = TrieNode.new
#
#  delegate add_char, [], []?, to: @root
#end

class TrieNode
  @children = StaticArray(TrieNode?, 26).new(nil)

  def [](w : Word, index_into_w = 0) : CharSet
    res = self[w, index_into_w]?
    if res.nil?
      raise ArgumentError.new
    else
      return res
    end
  end
  
  def []?(w : Word, index_into_w = 0) : CharSet?
    if index_into_w == w.size || w[index_into_w] == 0u8
      res = CharSet.new
      26.times do |i|
        res.add_char (i+97).to_u8 unless @children[i].nil?
      end
      return res
    else
      a = @children[w[index_into_w]-97]
      return nil if a.nil?
      return a[w, index_into_w]?
    end
  end
  
  def add_char(char : UInt8, index_w : Word, index_into_word = 0) : Nil
    unless 'a'.ord <= char && char <= 'z'.ord
      raise ArgumentError.new()
    end
    return if index_w.size == index_into_word || index_w[index_into_word] == 0_u8
    get_or_create_child(index_w[index_into_word]).add_char(char, index_w, index_into_word + 1)
  end

  def get_child(char : UInt8)
    @children[char - 'a'.ord]
  end

  def get_or_create_child(char : UInt8) : TrieNode
    unless 'a'.ord <= char && char <= 'z'.ord
      raise ArgumentError.new(char.to_s)
    end
    char_i = char - 'a'.ord
    if @children[char_i].nil?
      @children[char_i] = TrieNode.new()
    end
    c = @children[char_i].not_nil!
    return c
  end
end
  
