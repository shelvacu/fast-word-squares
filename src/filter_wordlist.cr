require "./square_size"

# Reads the file given, and returns an array of Words that:
#
# * Are SQUARE_SIZE characters long
# * Are normalized to all downcase
# * Only contain the ascii codes 'a' through 'z' after normalization of case.
def filtered_wordlist(wordlist_fn) : Array(Word)
  File.read(wordlist_fn)
    .split
    .reject{|word| word.size != SQUARE_SIZE || !word.chars.all?{|c| 'a' <= c && c <= 'z'}}
    .map{|word| word.downcase}
    .map do |word_str|
    word_sa = Word.new(0u8)
    SQUARE_SIZE.times do |i|
      word_sa[i] = word_str[i].ord.to_u8
    end
    word_sa
  end
end
