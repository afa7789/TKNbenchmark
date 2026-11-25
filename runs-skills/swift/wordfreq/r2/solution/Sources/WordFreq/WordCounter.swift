/// Counts case-insensitive words, where a word is a maximal run of ASCII letters.
///
/// Input may be fed in arbitrary chunks; a word split across chunk boundaries
/// is joined correctly. Every non-letter byte acts as a separator.
public struct WordCounter {
    public private(set) var counts: [String: Int] = [:]
    private var pending: [UInt8] = []

    public init() {
        pending.reserveCapacity(64)
    }

    /// Feeds a chunk of raw bytes.
    public mutating func consume(_ bytes: some Sequence<UInt8>) {
        for byte in bytes {
            if let lower = Self.lowercasedLetter(byte) {
                pending.append(lower)
            } else {
                flush()
            }
        }
    }

    /// Feeds the UTF-8 bytes of a string.
    public mutating func consume(_ text: String) {
        var text = text
        text.withUTF8 { consume($0) }
    }

    /// Completes any word still in progress. Call once input is exhausted.
    public mutating func finish() {
        flush()
    }

    /// The `limit` most frequent words, by count descending then word ascending (byte order).
    public func top(_ limit: Int) -> [(word: String, count: Int)] {
        counts
            .map { (word: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count : lhs.word.utf8.lexicographicallyPrecedes(rhs.word.utf8)
            }
            .prefix(limit)
            .map { $0 }
    }

    private mutating func flush() {
        guard !pending.isEmpty else { return }
        counts[String(decoding: pending, as: UTF8.self), default: 0] += 1
        pending.removeAll(keepingCapacity: true)
    }

    @inline(__always)
    private static func lowercasedLetter(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"): byte
        case UInt8(ascii: "A")...UInt8(ascii: "Z"): byte | 0x20
        default: nil
        }
    }
}

/// Formats ranked entries as `<count> <word>` lines, each terminated by a newline.
public func formatReport(_ entries: [(word: String, count: Int)]) -> String {
    entries.map { "\($0.count) \($0.word)\n" }.joined()
}
