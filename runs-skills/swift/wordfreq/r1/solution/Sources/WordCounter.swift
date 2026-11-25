/// Counts case-insensitive words, where a word is a maximal run of ASCII letters.
///
/// Input may be fed in arbitrary chunks; a word spanning two chunks is joined correctly.
public struct WordCounter {
    public struct Entry: Equatable, Sendable {
        public let word: String
        public let count: Int

        public init(word: String, count: Int) {
            self.word = word
            self.count = count
        }
    }

    private var counts: [String: Int] = [:]
    /// Lowercased bytes of the word currently being scanned.
    private var pending: [UInt8] = []

    public init() {
        pending.reserveCapacity(64)
    }

    /// Scans a chunk of raw bytes.
    public mutating func feed<Bytes: Sequence>(_ bytes: Bytes) where Bytes.Element == UInt8 {
        for byte in bytes {
            // Folding bit 0x20 maps 'A'...'Z' onto 'a'...'z' and leaves lowercase intact.
            let lower = byte | 0x20
            if lower >= UInt8(ascii: "a") && lower <= UInt8(ascii: "z") {
                pending.append(lower)
            } else if !pending.isEmpty {
                flush()
            }
        }
    }

    /// Ends the current word, if any. Call after the last chunk.
    public mutating func finish() {
        if !pending.isEmpty { flush() }
    }

    private mutating func flush() {
        counts[String(decoding: pending, as: UTF8.self), default: 0] += 1
        pending.removeAll(keepingCapacity: true)
    }

    /// The `limit` most frequent words, by count descending, then word ascending (byte order).
    public func top(_ limit: Int) -> [Entry] {
        guard limit > 0 else { return [] }
        var best: [Entry] = []
        best.reserveCapacity(limit + 1)
        for (word, count) in counts {
            let entry = Entry(word: word, count: count)
            if best.count == limit, let last = best.last, !Self.precedes(entry, last) {
                continue
            }
            let index = best.firstIndex { Self.precedes(entry, $0) } ?? best.endIndex
            best.insert(entry, at: index)
            if best.count > limit { best.removeLast() }
        }
        return best
    }

    private static func precedes(_ a: Entry, _ b: Entry) -> Bool {
        if a.count != b.count { return a.count > b.count }
        // Words are pure ASCII, so String ordering equals byte ordering.
        return a.word < b.word
    }
}

extension WordCounter {
    /// Formats entries as `<count> <word>` lines.
    public static func render(_ entries: [Entry]) -> String {
        var output = ""
        for entry in entries {
            output += "\(entry.count) \(entry.word)\n"
        }
        return output
    }
}
