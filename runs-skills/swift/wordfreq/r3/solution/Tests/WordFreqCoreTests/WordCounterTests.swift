import Testing
import WordFreqCore

@Suite struct WordCounterTests {
    private func top(_ text: String, limit: Int = 10) -> [WordCount] {
        WordCounter.mostFrequent(in: Array(text.utf8), limit: limit)
    }

    @Test func countsAndOrders() {
        #expect(top("The cat and the hat.").formattedReport() == "2 the\n1 and\n1 cat\n1 hat\n")
    }

    @Test func emptyInputYieldsNothing() {
        #expect(top("").isEmpty)
        #expect(top("123 _ ' -- \u{00E9}").isEmpty)
    }

    @Test func separators() {
        #expect(top("don't stop_me 4now, now-NOW").formattedReport() == "3 now\n1 don\n1 me\n1 stop\n1 t\n")
    }

    @Test func nonASCIIBytesSeparate() {
        let bytes: [UInt8] = [0x61, 0xFF, 0x61, 0xC3, 0x28, 0x41, 0x80]
        #expect(WordCounter.mostFrequent(in: bytes, limit: 10) == [WordCount(word: "a", count: 3)])
    }

    @Test func limitsToTen() {
        let words = (0..<26).map { String(UnicodeScalar(UInt8(ascii: "a") + UInt8($0))) }
        let result = top(words.reversed().joined(separator: " "))
        #expect(result.map(\.word) == Array(words.prefix(10)))
    }

    @Test func wordsSpanningChunks() {
        var counter = WordCounter()
        for chunk in ["he", "LL", "o wor", "ld hel", "lo", " ", "x"] {
            counter.consume(Array(chunk.utf8))
        }
        counter.finish()
        #expect(counter.mostFrequent(10) == [
            WordCount(word: "hello", count: 2),
            WordCount(word: "world", count: 1),
            WordCount(word: "x", count: 1),
        ])
    }

    @Test func manyDistinctWordsSurviveGrowth() {
        var text = ""
        for i in 0..<20_000 {
            var n = i
            var word = ""
            repeat {
                word.append(Character(UnicodeScalar(UInt8(ascii: "a") + UInt8(n % 26))))
                n /= 26
            } while n > 0
            text += word + (i % 3 == 0 ? " \(word.uppercased()) " : " ")
        }
        var counter = WordCounter()
        counter.consume(Array(text.utf8))
        counter.finish()
        #expect(counter.distinctWordCount == 20_000)
        #expect(counter.mostFrequent(1).first?.count == 2)
    }
}
