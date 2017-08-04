#####
#
# ## Documentation of compile flags
#
# * square_size_N
#   The only required compile option, designates the size (order)
#   of the squares to be computed.
#   Replace N with a number between 1 and 11 inclusive.
#
# * himem
#   Use a different indexing algorithm using a very large
#   but sparse section of memory.
#
#   Uses 2^(5×SQUARE_SIZE+2) bytes of memory. Due to many bugs in
#   Crystal, this cannot be used for square_size_6 or greater
#
# * fill_alt_blah, fill_really_diag
#   Fill in the square in a different order. Initial testing shows
#   that the default order is the fastest.
#
# * record_stops
#   Records and displays the number of times the CharSet was empty
#   (ie. the algorithm hit a dead end) for each cell. Hypothetically
#   may be useful for determining how to make things faster.
#
# * pretty_output
#   Instead of one result per line, display each square on multiple
#   lines such that the squareness is obvious. Useful for show.
#
# * stop_after_60s
#   Does what it says on the tin with a caviot: This will only stop
#   directly after a result is printed; If no results are given then
#   this will never stop.
#
# * square_buffer
#   Add an output buffer, such that brief output blocks will not
#   block computation. Probably not useful in most cases.
#
# * disable_gc
#   This disables the garbage collector during the actual computation
#   for a small performance gain.
#   Implies allocless_puts_sq
#
# * allocless_compute
#   This prints squares in a different format (excludes the flipped
#   version of the square) and is slightly faster. This is because this
#   implementation does not do anything that would cause a malloc.
#   Implied by disable_gc

{% if flag?(:square_size_11) %}
  SQUARE_SIZE = 11
{% elsif flag?(:square_size_10) %}
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
{% if flag?(:trie) %}
  require "./trie"
{% end %}

class GlobalVars
  @@wordlist_fn : String = ""
  @@start_chars : String = ""
  @@fill_to : UInt8 = (SQUARE_AREA-1).to_u8

  class_property wordlist_fn, start_chars, fill_to
end

OptionParser.parse! do |pr|
  pr.banner = "Usage: #{$0} [arguments]"
  pr.on("-w WORDLIST", "--wordlist WORDLIST", "Filename of the wordlist to use [REQUIRED]") {|arg| GlobalVars.wordlist_fn = arg}
  pr.on("-s CHARS", "--start CHARS", "Only search for squares starting with CHARS. Order is dependent on compiler flags") {|c| GlobalVars.start_chars = c}
  pr.on("-a SIZE", "--assert-size SIZE", "Assert that this program was compiled for finding squares of order SIZE") do |s|
    s_i = s.to_i
    raise "-a/--assert-size failed, compiled order is #{SQUARE_SIZE}, argument was #{s_i}" unless SQUARE_SIZE == s_i
  end
  pr.on("-f SIZE", "--fill-to SIZE", "Fill the square until SIZE chars have been placed, then return the (potentially incomplete) squares.") do |s|
    GlobalVars.fill_to = s.to_u8
  end
  pr.on("-h", "--help", "Print this help message") {puts pr;exit}
end

raise "Wordlist is required." unless GlobalVars.wordlist_fn != ""

SQUARE_AREA = (SQUARE_SIZE * SQUARE_SIZE)
alias Word = StaticArray(UInt8, SQUARE_SIZE)

words = File.read(GlobalVars.wordlist_fn)
        .split
        .reject{|word| word.size != SQUARE_SIZE || !word.chars.all?{|c| 'a' <= c && c <= 'z'}}
        .map{|word| word.downcase}
        .map do |word_str|
  #word_str.chars.each do |ch|
  #  unless 'a' <= ch && ch <= 'z'
  #    next #skip this word
  #  end
  #end
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
      if (@internal & (2_u32**i)) != 0
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
    # The 5 here is because this uses 5 bits per character
    BUFF_SIZE = (2**(SQUARE_SIZE.to_u64*5))

    @initialized = Set(UInt64).new

    def initialize
      STDERR.puts "Allocating #{BUFF_SIZE*sizeof(CharSet)} bytes of memory"
      #@buff = Slice(CharSet).new(BUFF_SIZE, CharSet.new)
      #@buff = uninitialized CharSet[BUFF_SIZE]
      @buff = Pointer(CharSet).malloc(BUFF_SIZE)
      @buff[0] = CharSet.new((2u32**27)-1)
      @initialized.add(0u64)
    end

    def [](idx : Word)
      #res = @buff[word_index_to_int_index(idx)]
      #puts "Grabbing #{idx} which is #{res}"
      return @buff[word_index_to_int_index(idx)] #res
    end

    def []?(idx : Word)
      return self[idx]
    end

    def add_char(char : UInt8, index : Word)
      i_index = word_index_to_int_index(index)
      if !@initialized.includes?(i_index)
        @buff[i_index] = CharSet.new
        @initialized.add(i_index)
      end
      cs = @buff[i_index]
      cs.add_char(char)
      @buff[i_index] = cs
    end

    def bytes_used
      return @initialized.size * sizeof(CharSet)
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
{% elsif flag?(:trie) %}
  INDEXED_WORDS = TrieNode.new
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
words.each do |word|
  #puts "Processing #{word}"
  {% if flag?(:trie) %}
    INDEXED_WORDS.add_word word
  {% else %}
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
  {% end %}
end

words = nil

{% if flag?(:himem) %}
  STDERR.puts "Actually used #{INDEXED_WORDS.bytes_used} bytes."
{% end %}

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

def stringize_sq(sq : Square)
  end_str : String
  join_str : String
  {% if flag?(:pretty_output) %}
    join_str = "\n"
    end_str = ""
  {% else %}
    join_str = "-"
    end_str = " / " +
              SQUARE_SIZE.times.map{|i| sq.map{|wd| wd[i].chr}.join}.join("-")
  {% end %}
  return (
    sq.map{|wd| wd.map(&.chr).join}.join(join_str) + end_str
  ).chars.map{|c| c == '\0' ? '*' : c}.join
end

def recurse(sq : Square,
            column : UInt8 = 0u8,
            row : UInt8 = 0u8,
            fill_to : UInt8 = (SQUARE_AREA-1).to_u8,
            filled : UInt8 = 0u8,
            &block : Square ->)
  #STDERR.puts stringize_sq(sq)
  #STDERR.puts "running recurse with c:#{column}, r:#{row}"
  if filled > fill_to
    #STDERR.puts "yielding"
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
  #puts "col_wd: #{col_wd.map(&.chr).join.gsub('\0','*')}, row_wd: #{row_wd.map(&.chr).join.gsub('\0','*')}"
  #puts "col_posi: #{col_posi}, row_posi: #{row_posi}, posi: #{posi}"
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

def puts_sq(sq : Square)
  {% if flag?(:pretty_output) %}
    puts
  {% end %}
  puts stringize_sq(sq)
end

# buf must be in format xxxxx-xxxxx-xxxxx-xxxxx-xxxxx followed by a newline
def allocless_puts_sq(sq : Square, buf : Bytes)
  if buf.size != SQUARE_AREA + SQUARE_SIZE
    raise ArgumentError.new("Incorrectly sized buf")
  end
  sq.each_with_index do |wd, wd_i|
    wd.each_with_index do |chr, chr_i|
      buf[ (wd_i*(SQUARE_SIZE+1)) + chr_i ] = chr
    end
  end
  STDOUT.write(buf)
end

{% if flag?(:square_buffer) %}
  output_chan = Channel(Square).new(250_000)
  output_thr_done_chan = Channel(Nil).new
  output_thr = spawn do
    loop do
      sq = output_chan.receive
      break if sq[0][0] == 0u8 #special signal to exit
      puts_sq sq
    end
    output_thr_done_chan.send(nil)
  end
{% end %}

#STDERR.puts stringize_sq start_square
STDERR.puts "Starting at col #{start_col}, row #{start_row}, fill to #{GlobalVars.fill_to}"

{% if flag?(:disable_gc) %}
  GC.disable
{% end %}
{% if flag?(:disable_gc) || flag?(:allocless_compute) %}
  buf = (SQUARE_SIZE.times.map{ SQUARE_SIZE.times.map{"*"}.join }.join("-") + "\n").to_slice.clone
{% end %}

recurse(start_square, start_col, start_row, GlobalVars.fill_to, GlobalVars.start_chars.size.to_u8) do |sq|
  {% if flag?(:square_buffer) %}
    output_chan.send(sq)
  {% elsif flag?(:disable_gc) || flag?(:allocless_compute) %}
    allocless_puts_sq(sq, buf)
  {% else %}
    puts_sq(sq)
  {% end %}
  {% if flag?(:stop_after_60s) %}
    exit if (Time.now - start).minutes > 0
  {% end %}
end

{% if flag?(:disable_gc) %}
  GC.enable
{% end %}

{% if flag?(:square_buffer) %}
  output_chan.send(Square.new(Word.new(0u8)))
  output_thr_done_chan.receive
{% end %}

{% if flag?(:record_time) %}
  STDERR.puts Time.now - start
{% end %}
{% if flag?(:record_stops) %}
  STDERR.puts StopRecorder.stop_record
{% end %}
STDERR.puts "done"
