import Testing
import WordFreq

@Suite struct WordCounterTests {
    private func report(_ input: String) -> String {
        var counter = WordCounter()
        counter.consume(input)
        counter.finish()
        return formatReport(counter.top(10))
    }

    @Test func example() {
        #expect(report("The cat and the hat.") == "2 the\n1 and\n1 cat\n1 hat\n")
    }

    @Test func separators() {
        #expect(report("don't stop_me 4now, now-NOW") == "3 now\n1 don\n1 me\n1 stop\n1 t\n")
    }

    @Test func emptyInput() {
        #expect(report("").isEmpty)
        #expect(report("123 ... \u{e9}").isEmpty)
    }

    @Test func wordSplitAcrossChunks() {
        var counter = WordCounter()
        counter.consume(Array("hel".utf8))
        counter.consume(Array("LO wor".utf8))
        counter.consume([0xFF])
        counter.consume(Array("ld".utf8))
        counter.finish()
        #expect(formatReport(counter.top(10)) == "1 hello\n1 ld\n1 wor\n")
    }

    @Test func limitsToTen() {
        let words = (0..<15).map { "w" + String(repeating: "a", count: $0 + 1) }
        #expect(report(words.joined(separator: " ")).split(separator: "\n").count == 10)
    }
}
