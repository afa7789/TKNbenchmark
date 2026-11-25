import WordFreq

var counter = WordCounter()
// Invalid UTF-8 is repaired to U+FFFD, whose bytes are all >= 0x80 and thus
// separators, so word boundaries are preserved exactly.
while let line = readLine(strippingNewline: false) {
    counter.consume(line)
}
counter.finish()
print(formatReport(counter.top(10)), terminator: "")
