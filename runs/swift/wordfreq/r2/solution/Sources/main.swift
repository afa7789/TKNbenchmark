// wordfreq: print the 10 most frequent ASCII words read from standard input.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Open-addressing hash table counting byte-string words.
/// Word bytes live in a single arena to avoid a heap allocation per word.
struct WordTable {
    private struct Slot {
        var hash: UInt64 = 0
        var offset: Int32 = 0
        var length: Int32 = 0  // 0 marks an empty slot; words are never empty.
        var count: Int = 0
    }

    private var slots: [Slot]
    private var mask: Int
    private var arena: [UInt8] = []
    private(set) var distinctCount = 0

    init(initialCapacity: Int = 1 << 14) {
        var capacity = 16
        while capacity < initialCapacity { capacity <<= 1 }
        slots = Array(repeating: Slot(), count: capacity)
        mask = capacity - 1
    }

    /// Increments the count of `word`, whose precomputed hash is `hash`.
    mutating func increment(_ word: UnsafeBufferPointer<UInt8>, hash: UInt64) {
        var index = Int(truncatingIfNeeded: hash) & mask
        while true {
            let slot = slots[index]
            if slot.length == 0 { break }
            if slot.hash == hash && Int(slot.length) == word.count && matches(slot, word) {
                slots[index].count += 1
                return
            }
            index = (index + 1) & mask
        }
        slots[index] = Slot(
            hash: hash,
            offset: Int32(arena.count),
            length: Int32(word.count),
            count: 1
        )
        arena.append(contentsOf: word)
        distinctCount += 1
        if distinctCount * 2 > slots.count { grow() }
    }

    private func matches(_ slot: Slot, _ word: UnsafeBufferPointer<UInt8>) -> Bool {
        arena.withUnsafeBufferPointer { arena in
            let start = Int(slot.offset)
            for i in 0..<word.count where arena[start + i] != word[i] {
                return false
            }
            return true
        }
    }

    private mutating func grow() {
        let old = slots
        slots = Array(repeating: Slot(), count: old.count * 2)
        mask = slots.count - 1
        for slot in old where slot.length != 0 {
            var index = Int(truncatingIfNeeded: slot.hash) & mask
            while slots[index].length != 0 { index = (index + 1) & mask }
            slots[index] = slot
        }
    }

    /// All words with their counts.
    var entries: [(word: [UInt8], count: Int)] {
        slots.lazy.filter { $0.length != 0 }.map { slot in
            let start = Int(slot.offset)
            return (word: Array(arena[start..<start + Int(slot.length)]), count: slot.count)
        }
    }
}

/// Counts case-folded words, where a word is a maximal run of ASCII letters.
/// Input may arrive in arbitrary chunks; words spanning chunk boundaries are handled.
struct WordCounter {
    private static let fnvOffset: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let fnvPrime: UInt64 = 0x0000_0100_0000_01b3

    private var table = WordTable()
    private var current: [UInt8] = []
    private var hash = fnvOffset

    init() {
        current.reserveCapacity(64)
    }

    mutating func consume(_ bytes: UnsafeBufferPointer<UInt8>) {
        for byte in bytes {
            // Setting bit 0x20 maps 'A'...'Z' onto 'a'...'z'; the only bytes that
            // land in 'a'...'z' afterwards are the ASCII letters themselves.
            let folded = byte | 0x20
            if folded &- UInt8(ascii: "a") < 26 {
                current.append(folded)
                hash = (hash ^ UInt64(folded)) &* Self.fnvPrime
            } else if !current.isEmpty {
                flush()
            }
        }
    }

    /// Records any word still pending at end of input.
    mutating func finish() {
        if !current.isEmpty { flush() }
    }

    private mutating func flush() {
        current.withUnsafeBufferPointer { table.increment($0, hash: hash) }
        current.removeAll(keepingCapacity: true)
        hash = Self.fnvOffset
    }

    /// The `limit` most frequent words, by count descending then word ascending (byte order).
    func top(_ limit: Int) -> [(word: [UInt8], count: Int)] {
        let ranked = table.entries.sorted { lhs, rhs in
            lhs.count != rhs.count ? lhs.count > rhs.count : lhs.word.lexicographicallyPrecedes(rhs.word)
        }
        return Array(ranked.prefix(limit))
    }
}

/// Feeds all of standard input to `body` in chunks.
func readStandardInput(_ body: (UnsafeBufferPointer<UInt8>) -> Void) {
    let capacity = 1 << 16
    let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: capacity)
    defer { buffer.deallocate() }
    while true {
        let n = read(STDIN_FILENO, buffer.baseAddress, capacity)
        if n > 0 {
            body(UnsafeBufferPointer(rebasing: buffer[..<n]))
        } else if n == 0 || errno != EINTR {
            return
        }
    }
}

var counter = WordCounter()
readStandardInput { counter.consume($0) }
counter.finish()

var output = ""
for (word, count) in counter.top(10) {
    output += "\(count) \(String(decoding: word, as: UTF8.self))\n"
}
print(output, terminator: "")
