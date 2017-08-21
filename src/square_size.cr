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

SQUARE_AREA = (SQUARE_SIZE * SQUARE_SIZE)
alias Word = StaticArray(UInt8, SQUARE_SIZE)
alias Square = StaticArray(Word, SQUARE_SIZE)

#struct Word
#  @internal : StaticArray(UInt8, SQUARE_SIZE)
#
#  def initialize(*args)
#    @internal = StaticArray(UInt8, SQUARE_SIZE).new(*args)
#  end
#  
#  def to_s(io : IO)
#    self.each do |b|
#      io.write_byte(b)
#    end
#  end
#
#  macro method_missing(call)
#    @internal.{{call.name.id}}({{call.args.join(",").id}})
#  end
#end
