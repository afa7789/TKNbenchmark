/// A word together with the number of times it occurred.
public struct WordCount: Equatable, Sendable {
    public var word: String
    public var count: Int

    public init(word: String, count: Int) {
        self.word = word
        self.count = count
    }
}

/// Counts case-insensitive words in a stream of bytes.
///
/// A word is a maximal run of ASCII letters; every other byte is a separator.
/// Input may be fed in arbitrary chunks via ``consume(_:)``; words that span
/// chunk boundaries are handled transparently. Call ``finish()`` after the last
/// chunk so a trailing word is counted.
///
/// Internally, distinct words are stored lowercased in a single byte arena and
/// indexed by an open-addressing hash table, so counting allocates nothing per word.
public struct WordCounter {
    private struct Entry {
        var offset: Int
        var length: Int
        var hash: UInt64
        var count: Int
    }

    private static let fnvOffset: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let fnvPrime: UInt64 = 0x0000_0100_0000_01b3
    private static let emptySlot = -1

    /// Lowercased bytes of every distinct word, back to back.
    private var arena: [UInt8] = []
    private var entries: [Entry] = []
    /// Open-addressing table of indices into `entries`; `emptySlot` marks a free slot.
    private var slots: [Int]
    /// Raw bytes of a word that started in an earlier chunk and has not ended yet.
    private var pending: [UInt8] = []
    /// Running hash of the word currently being scanned.
    private var runningHash = WordCounter.fnvOffset

    public init() {
        slots = Array(repeating: Self.emptySlot, count: 1 << 12)
    }

    /// The number of distinct words seen so far.
    public var distinctWordCount: Int { entries.count }

    /// Feeds the next chunk of input.
    public mutating func consume(_ bytes: UnsafeBufferPointer<UInt8>) {
        var hash = runningHash
        var wordStart: Int? = pending.isEmpty ? nil : 0

        for (index, byte) in bytes.enumerated() {
            let lowered = byte | 0x20
            if lowered >= UInt8(ascii: "a") && lowered <= UInt8(ascii: "z") {
                if wordStart == nil { wordStart = index }
                hash = (hash ^ UInt64(lowered)) &* Self.fnvPrime
            } else if let start = wordStart {
                if pending.isEmpty {
                    record(UnsafeBufferPointer(rebasing: bytes[start..<index]), hash: hash)
                } else {
                    pending.append(contentsOf: bytes[0..<index])
                    flushPending(hash: hash)
                }
                wordStart = nil
                hash = Self.fnvOffset
            }
        }

        if let start = wordStart {
            // The word continues into the next chunk (if any): stash what we have.
            pending.append(contentsOf: bytes[start...])
        }
        runningHash = hash
    }

    /// Feeds the next chunk of input.
    public mutating func consume(_ bytes: some Sequence<UInt8>) {
        let handled: Void? = bytes.withContiguousStorageIfAvailable { consume($0) }
        if handled == nil {
            Array(bytes).withUnsafeBufferPointer { consume($0) }
        }
    }

    /// Signals end of input, counting any word still in progress.
    public mutating func finish() {
        if !pending.isEmpty {
            flushPending(hash: runningHash)
        }
        runningHash = Self.fnvOffset
    }

    /// Returns up to `limit` words ordered by count descending, then by word
    /// ascending in byte order.
    public func mostFrequent(_ limit: Int) -> [WordCount] {
        guard limit > 0 else { return [] }

        return arena.withUnsafeBufferPointer { arena in
            func bytes(of entry: Entry) -> UnsafeBufferPointer<UInt8> {
                UnsafeBufferPointer(rebasing: arena[entry.offset..<entry.offset + entry.length])
            }
            func ranksBefore(_ lhs: Entry, _ rhs: Entry) -> Bool {
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return bytes(of: lhs).lexicographicallyPrecedes(bytes(of: rhs))
            }

            // Bounded selection: `top` stays sorted best-first and holds at most `limit` entries.
            var top: [Entry] = []
            top.reserveCapacity(limit + 1)
            for entry in entries {
                if top.count == limit, let worst = top.last, !ranksBefore(entry, worst) {
                    continue
                }
                let position = top.firstIndex { ranksBefore(entry, $0) } ?? top.endIndex
                top.insert(entry, at: position)
                if top.count > limit { top.removeLast() }
            }

            return top.map { entry in
                WordCount(word: String(decoding: bytes(of: entry), as: UTF8.self), count: entry.count)
            }
        }
    }

    // MARK: - Hash table

    private mutating func flushPending(hash: UInt64) {
        var word = pending
        pending = []
        word.withUnsafeBufferPointer { record($0, hash: hash) }
        word.removeAll(keepingCapacity: true)
        pending = word
    }

    /// Increments the count of `word` (raw ASCII letters, any case) whose
    /// lowercase FNV-1a hash is `hash`.
    private mutating func record(_ word: UnsafeBufferPointer<UInt8>, hash: UInt64) {
        let mask = slots.count - 1
        var slot = Self.slotIndex(for: hash, mask: mask)

        while true {
            let entryIndex = slots[slot]
            if entryIndex == Self.emptySlot { break }
            let entry = entries[entryIndex]
            if entry.hash == hash && entry.length == word.count && matches(word, at: entry.offset) {
                entries[entryIndex].count += 1
                return
            }
            slot = (slot + 1) & mask
        }

        let offset = arena.count
        arena.append(contentsOf: word.lazy.map { $0 | 0x20 })
        slots[slot] = entries.count
        entries.append(Entry(offset: offset, length: word.count, hash: hash, count: 1))

        if entries.count * 2 > slots.count {
            grow()
        }
    }

    private func matches(_ word: UnsafeBufferPointer<UInt8>, at offset: Int) -> Bool {
        arena.withUnsafeBufferPointer { arena in
            for (index, byte) in word.enumerated() where arena[offset + index] != byte | 0x20 {
                return false
            }
            return true
        }
    }

    private mutating func grow() {
        let capacity = slots.count * 2
        let mask = capacity - 1
        var resized = Array(repeating: Self.emptySlot, count: capacity)
        for (entryIndex, entry) in entries.enumerated() {
            var slot = Self.slotIndex(for: entry.hash, mask: mask)
            while resized[slot] != Self.emptySlot {
                slot = (slot + 1) & mask
            }
            resized[slot] = entryIndex
        }
        slots = resized
    }

    private static func slotIndex(for hash: UInt64, mask: Int) -> Int {
        // Fold high bits in: FNV-1a's low bits alone mix poorly for short keys.
        let mixed = (hash ^ (hash >> 32)) &* 0x9e37_79b9_7f4a_7c15
        return Int(truncatingIfNeeded: mixed >> 32) & mask
    }
}

extension WordCounter {
    /// Convenience: counts all words in `bytes` and returns the `limit` most frequent.
    public static func mostFrequent(in bytes: some Sequence<UInt8>, limit: Int) -> [WordCount] {
        var counter = WordCounter()
        counter.consume(bytes)
        counter.finish()
        return counter.mostFrequent(limit)
    }
}
