/// wordfreq: reads standard input and prints the 10 most frequent ASCII words.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Counts case-folded words, where a word is a maximal run of ASCII letters.
struct WordCounter {
    private(set) var counts: [String: Int] = [:]
    /// Lowercased bytes of the word currently being scanned; persists across chunks.
    private var current: [UInt8] = []

    init() {
        current.reserveCapacity(64)
    }

    /// Feeds a chunk of raw bytes. Words may span chunk boundaries.
    mutating func consume<Bytes: Sequence>(_ bytes: Bytes) where Bytes.Element == UInt8 {
        for byte in bytes {
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"):
                current.append(byte)
            case UInt8(ascii: "A")...UInt8(ascii: "Z"):
                current.append(byte | 0x20)
            default:
                flush()
            }
        }
    }

    /// Terminates the word in progress, if any.
    mutating func flush() {
        guard !current.isEmpty else { return }
        counts[String(decoding: current, as: UTF8.self), default: 0] += 1
        current.removeAll(keepingCapacity: true)
    }

    /// Returns up to `limit` entries ordered by count descending, then word ascending.
    func top(_ limit: Int) -> [(word: String, count: Int)] {
        counts
            .map { (word: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.word.utf8.lexicographicallyPrecedes($1.word.utf8) }
            .prefix(limit)
            .map { $0 }
    }
}

/// Streams raw bytes from standard input in fixed-size chunks, without any
/// text decoding, so arbitrary (including invalid UTF-8) input is handled as-is.
func readStandardInput(chunkSize: Int = 1 << 20, _ body: (UnsafeRawBufferPointer) -> Void) {
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: chunkSize, alignment: 1)
    defer { buffer.deallocate() }
    while true {
        let n = read(STDIN_FILENO, buffer.baseAddress, chunkSize)
        if n > 0 {
            body(UnsafeRawBufferPointer(rebasing: buffer[..<n]))
        } else if n == 0 || errno != EINTR {
            break
        }
    }
}

var counter = WordCounter()
readStandardInput { counter.consume($0) }
counter.flush()

let output = counter.top(10).map { "\($0.count) \($0.word)\n" }.joined()
print(output, terminator: "")
