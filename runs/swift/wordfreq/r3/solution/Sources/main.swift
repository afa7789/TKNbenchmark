// wordfreq: print the 10 most frequent ASCII words read from standard input.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Reads all of standard input into a byte array.
func readStandardInput() -> [UInt8] {
    var data: [UInt8] = []
    let chunkSize = 1 << 20
    var chunk = [UInt8](repeating: 0, count: chunkSize)
    while true {
        let count = chunk.withUnsafeMutableBytes { read(STDIN_FILENO, $0.baseAddress, chunkSize) }
        if count > 0 {
            data.append(contentsOf: chunk[0..<count])
        } else if count == 0 || errno != EINTR {
            break
        }
    }
    return data
}

/// A word occurrence count; the word itself is a slice of the (lowercased) input buffer.
struct WordEntry {
    var start: Int
    var length: Int
    var count: Int
}

/// Open-addressing hash table mapping byte slices of a shared buffer to counts.
/// Avoids allocating a key per word, which matters for large inputs.
struct WordCounter {
    private(set) var entries: [WordEntry] = []
    private var slots: [Int32]          // index into `entries`, or -1 when empty
    private var hashes: [UInt64]        // cached hash per entry, for cheap rehash/compare
    private var mask: Int

    init(initialCapacity: Int = 1 << 12) {
        var capacity = 1
        while capacity < initialCapacity { capacity <<= 1 }
        slots = [Int32](repeating: -1, count: capacity)
        hashes = []
        mask = capacity - 1
    }

    mutating func add(start: Int, length: Int, hash: UInt64, in buffer: UnsafeBufferPointer<UInt8>) {
        var slot = Int(truncatingIfNeeded: hash) & mask
        while true {
            let index = Int(slots[slot])
            if index < 0 { break }
            let entry = entries[index]
            if hashes[index] == hash && entry.length == length
                && memcmp(buffer.baseAddress! + entry.start, buffer.baseAddress! + start, length) == 0 {
                entries[index].count += 1
                return
            }
            slot = (slot + 1) & mask
        }
        slots[slot] = Int32(entries.count)
        entries.append(WordEntry(start: start, length: length, count: 1))
        hashes.append(hash)
        if entries.count * 2 > slots.count { grow() }
    }

    private mutating func grow() {
        let capacity = slots.count * 2
        slots = [Int32](repeating: -1, count: capacity)
        mask = capacity - 1
        for (index, hash) in hashes.enumerated() {
            var slot = Int(truncatingIfNeeded: hash) & mask
            while slots[slot] >= 0 { slot = (slot + 1) & mask }
            slots[slot] = Int32(index)
        }
    }
}

/// Lowercases ASCII letters in place and counts every maximal run of letters.
func countWords(in data: inout [UInt8]) -> WordCounter {
    var counter = WordCounter()
    data.withUnsafeMutableBufferPointer { bytes in
        let buffer = UnsafeBufferPointer(bytes)
        let fnvOffset: UInt64 = 0xcbf2_9ce4_8422_2325
        let fnvPrime: UInt64 = 0x0000_0100_0000_01b3
        var index = 0
        let end = bytes.count
        while index < end {
            // Skip separators.
            while index < end && !isASCIILetter(bytes[index]) { index += 1 }
            if index == end { break }
            let start = index
            var hash = fnvOffset
            while index < end {
                let byte = bytes[index]
                guard isASCIILetter(byte) else { break }
                let lower = byte | 0x20
                bytes[index] = lower
                hash = (hash ^ UInt64(lower)) &* fnvPrime
                index += 1
            }
            // Final avalanche so low bits (used for slot selection) are well mixed.
            hash ^= hash >> 33
            hash = hash &* 0xff51_afd7_ed55_8ccd
            hash ^= hash >> 33
            counter.add(start: start, length: index - start, hash: hash, in: buffer)
        }
    }
    return counter
}

@inline(__always)
func isASCIILetter(_ byte: UInt8) -> Bool {
    (byte | 0x20) &- UInt8(ascii: "a") < 26
}

/// Byte-wise lexicographic comparison of two words in the buffer.
func precedes(_ a: WordEntry, _ b: WordEntry, in data: [UInt8]) -> Bool {
    if a.count != b.count { return a.count > b.count }
    return data[a.start..<(a.start + a.length)]
        .lexicographicallyPrecedes(data[b.start..<(b.start + b.length)])
}

/// Returns the `limit` best entries in order, using a bounded selection rather than a full sort.
func topEntries(_ entries: [WordEntry], limit: Int, in data: [UInt8]) -> [WordEntry] {
    var top: [WordEntry] = []
    top.reserveCapacity(limit + 1)
    for entry in entries {
        if top.count == limit, let last = top.last, !precedes(entry, last, in: data) { continue }
        let position = top.firstIndex { precedes(entry, $0, in: data) } ?? top.count
        top.insert(entry, at: position)
        if top.count > limit { top.removeLast() }
    }
    return top
}

var input = readStandardInput()
let counter = countWords(in: &input)
let top = topEntries(counter.entries, limit: 10, in: input)

var output = ""
for entry in top {
    let word = String(decoding: input[entry.start..<(entry.start + entry.length)], as: UTF8.self)
    output += "\(entry.count) \(word)\n"
}
if !output.isEmpty {
    print(output, terminator: "")
}
exit(0)
