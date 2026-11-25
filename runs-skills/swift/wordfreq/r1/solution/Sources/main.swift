var counter = WordCounter()
// `readLine` repairs invalid UTF-8 with U+FFFD, which never consumes ASCII bytes,
// so every letter and separator survives intact.
while let line = readLine(strippingNewline: false) {
    counter.feed(line.utf8)
}
counter.finish()
print(WordCounter.render(counter.top(10)), terminator: "")
