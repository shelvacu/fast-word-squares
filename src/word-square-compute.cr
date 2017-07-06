{% if flag?(:square_size_10) %}
  SQUARE_SIZE = 10
{% elsif flag?(:square_size_9) %}
  SQUARE_SIZE = 9
{% elsif flag?(:square_size_8) %}
  SQUARE_SIZE = 8
{% elsif flag?(:square_size_7) %}
  SQUARE_SIZE = 7
{% elsif flag?(:square_size_6) %}
  SQUARE_SIZE = 6
{% elsif flag?(:square_size_5) %}
  SQUARE_SIZE = 5
{% elsif flag?(:square_size_4) %}
  SQUARE_SIZE = 4
{% elsif flag?(:square_size_3) %}
  SQUARE_SIZE = 3
{% elsif flag?(:square_size_2) %}
  SQUARE_SIZE = 2
{% elsif flag?(:square_size_1) %}
  SQUARE_SIZE = 1
{% else %}
  {% raise("you must specify one of the square_size_* compiler flags (eg square_size_4)") %}
{% end %}

require "option_parser"

class GlobalVars
  @@wordlist_fn : String = ""
  @@start_chars : String = ""
  @@fill_to : UInt8 = (SQUARE_AREA-1).to_u8

  class_property wordlist_fn, start_chars, fill_to
end

OptionParser.parse! do |pr|
  pr.banner = "Usage: #{$0} [arguments]"
  pr.on("-w WORDLIST", "--wordlist=WORDLIST", "Filename of the wordlist to use [REQUIRED]") {|arg| GlobalVars.wordlist_fn = arg}
  pr.on("-s CHARS", "--start=CHARS", "Only search for squares starting with CHARS. Order is dependent on compiler flags") {|c| GlobalVars.start_chars = c}
  pr.on("-a SIZE", "--assert-size=SIZE", "Assert that this program was compiled for finding squares of order SIZE") do |s|
    s_i = s.to_i
    raise "-a/--assert-size failed, compiled order is #{SQUARE_SIZE}, argument was #{s_i}" unless SQUARE_SIZE == s_i
  end
  pr.on("-f SIZE", "--fill-to=SIZE", "Fill the square until SIZE chars have been placed, then return the (potentially incomplete) squares.") do |s|
    GlobalVars.fill_to = s.to_u8
  end
  pr.on("-h", "--help", "Print this help message") {puts pr;exit}
end

raise "Wordlist is required." unless GlobalVars.wordlist_fn != ""

SQUARE_AREA = (SQUARE_SIZE * SQUARE_SIZE)
alias Word = StaticArray(UInt8, SQUARE_SIZE)

WORDS = File.read(GlobalVars.wordlist_fn).split.reject{|word| word.size != SQUARE_SIZE}.map{|word| word.downcase}.map do |word_str|
  word_str.chars.each do |ch|
    if ch.ord > 127
      next #skip this word
    end
  end
  word_sa = Word.new(0u8)
  SQUARE_SIZE.times do |i|
    word_sa[i] = word_str[i].ord.to_u8
  end
  word_sa
end

struct CharSet
  @internal : UInt32

  getter internal
  
  def initialize(@internal : UInt32 = 0u32)
  end

  def add_char(c : Char)
    add_char c.ord.to_u8
  end
  
  def add_char(c : UInt8)
    @internal |= (2.to_u32**(c - 97))
  end

  def remove_char(c : Char)
    remove_char c.ord.to_u8
  end
  
  def remove_char(c : UInt8)
    @interal &= (UInt32::MAX ^ (2.to_u32**(c - 97)))
  end

  def &(other : CharSet)
    return CharSet.new(@internal & other.internal)
  end

  def each
    26.times do |i|
      if (@internal & (2.to_u32**i)) != 0
        yield (i + 97).to_u8
      end
    end
  end

  def to_s(io : IO)
    self.each do |r|
      io.write_byte r
    end
  end
  
  def empty?
    @internal == 0
  end
end

{% if flag?(:himem) %}
  struct WordIndex
    BUFF_SIZE = (2**(5*SQUARE_SIZE))

    def initialize
      STDERR.puts "Initializing #{BUFF_SIZE*sizeof(CharSet)} bytes of memory"
      @buff = Slice(CharSet).new(BUFF_SIZE, CharSet.new)
      @buff[0] = CharSet.new((2u32**27)-1)
    end

    def [](idx : Word)
      #res = @buff[word_index_to_int_index(idx)]
      #puts "Grabbing #{idx} which is #{res}"
      return @buff[word_index_to_int_index(idx)] #res
    end

    def add_char(char : UInt8, index : Word)
      i_index = word_index_to_int_index(index)
      cs = @buff[i_index]
      cs.add_char(char)
      @buff[i_index] = cs
    end

    private def word_index_to_int_index(w : Word)
      #pack each char in idx into res, each using 5 bits
      res = 0u64
      w.each do |ch|
        res = (res << 5) | (ch & 0b0001_1111)
      end
      return res
    end
  end

  INDEXED_WORDS = WordIndex.new
{% else %}
  # Word here is actually used as a prefix, with the remaining values set to zero.
  INDEXED_WORDS = {} of Word => CharSet

  INDEXED_WORDS[Word.new(0u8)] = CharSet.new((2u32**27)-1)
{% end %}

STDERR.puts "indexing"

#{% if flag?(:expansive_index) %}
#  WORDS.each do |word|
#    # TODO: Make an index of every substring
#  end
#{% else %}
WORDS.each do |word|
  (1...SQUARE_SIZE).each do |i|
    key = word.dup
    i.times do |j|
      key[-(j+1)] = 0u8
    end
    {% if flag?(:himem) %}
      INDEXED_WORDS.add_char(word[-i], key)
    {% else %}
      if !INDEXED_WORDS.has_key?(key)
        INDEXED_WORDS[key] = CharSet.new
      end
      cs = INDEXED_WORDS[key]
      cs.add_char(word[-i])
      INDEXED_WORDS[key] = cs
    {% end %}
  end
end

STDERR.puts "index finished"

alias Square = StaticArray(Word, SQUARE_SIZE)

@[AlwaysInline]
def next_pos(column : UInt8, row : UInt8) : {UInt8, UInt8}
  {% if flag?(:fill_alt_blah) %}
    if column == SQUARE_SIZE-1
      return row, row+1
    elsif row == SQUARE_SIZE-1
      return column+1, column+1
    elsif column >= row
      return column+1, row
    else
      return column, row+1
    end
  {% elsif flag?(:fill_really_diag) %}
    if row == 4
      return (SQUARE_SIZE-1).to_u8, column + 1
    elsif column == 0
      return row+1, 0u8
    else
      return column-1, row+1
    end
  {% else %}
    if column == (SQUARE_SIZE-1)
      return 0u8, row+1
    else
      return column+1, row
    end
  {% end %}
  raise "Should've returned but didnt"
end

{% if flag?(:record_stops) %}
  class StopRecorder
    @@stop_record = StaticArray(UInt64, SQUARE_AREA).new(0u64)

    def self.stop_record
      @@stop_record
    end

    def self.increment(idx)
      @@stop_record[idx] += 1
    end
  end
{% end %}

def recurse(sq : Square,
            column : UInt8 = 0u8,
            row : UInt8 = 0u8,
            fill_to : UInt8 = (SQUARE_AREA-1).to_u8,
            filled : UInt8 = 0u8,
            &block : Square -> Nil)
  #STDERR.puts "running recurse with c:#{column}, r:#{row}"
  if fill_to == filled
    yield sq
    return
  end
  col_wd = Word.new(0u8)
  row_wd = Word.new(0u8)
  row.times do |r|
    col_wd[r] = sq[r][column]
  end
  column.times do |c|
    row_wd[c] = sq[row][c]
  end
  col_posi = INDEXED_WORDS[col_wd]? || CharSet.new
  row_posi = INDEXED_WORDS[row_wd]? || CharSet.new
  posi = col_posi & row_posi
  new_col, new_row = next_pos(column,row)
  {% if flag?(:record_stops) %}
    StopRecorder.increment((row*SQUARE_SIZE) + column) if posi.empty?
  {% end %}
  posi.each do |char_u8|
    r = sq[row]
    r[column] = char_u8
    sq[row] = r
    recurse(sq, new_col, new_row, fill_to, filled+1, &block)
  end
end

STDERR.puts "starting"

{% if flag?(:stop_after_60s) || flag?(:record_time) %}
  start = Time.now
{% end %}

start_square = Square.new(Word.new(0u8))
start_col = 0u8
start_row = 0u8

GlobalVars.start_chars.each_codepoint do |code|
  raise "start chars invalid, only ascii is allowed!" if code > 127
  r = start_square[start_row]
  r[start_col] = code.to_u8
  start_square[start_row] = r
  start_col, start_row = next_pos(start_col, start_row)
end

recurse(start_square, start_col, start_row, GlobalVars.fill_to) do |sq|
  puts (
    sq.map{|wd| wd.map(&.chr).join}.join("-") +
    " / " +
    SQUARE_SIZE.times.map{|i| sq.map{|wd| wd[i].chr}.join}.join("-")
  ).chars.map{|c| c == '\0' ? '*' : c}.join
  {% if flag?(:stop_after_60s) %}
    exit if (Time.now - start).minutes > 0
  {% end %}
end

{% if flag?(:record_time) %}
  STDERR.puts Time.now - start
{% end %}
{% if flag?(:record_stops) %}
  STDERR.puts StopRecorder.stop_record
{% end %}
STDERR.puts "done"
