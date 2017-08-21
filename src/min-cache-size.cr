require "./filter_wordlist"

bla = Set(Word).new

filtered_wordlist(ARGV[0]).each do |word|
  (0..SQUARE_SIZE).each do |i|
    key = word
    i.times do |j|
      key[-(j+1)] = 0u8
    end
    bla.add(key)
  end
end

puts bla.size
puts bla.size * sizeof(UInt32)
