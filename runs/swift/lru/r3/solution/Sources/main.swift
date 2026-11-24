/// Reads an LRU capacity followed by cache commands from standard input and
/// writes each command's result to standard output.

/// Buffers output and flushes it in large chunks to keep I/O cheap.
struct OutputBuffer {
    private var buffer = ""
    private let flushThreshold = 1 << 16

    init() {
        buffer.reserveCapacity(flushThreshold * 2)
    }

    mutating func writeLine<S: StringProtocol>(_ line: S) {
        buffer += line
        buffer += "\n"
        if buffer.utf8.count >= flushThreshold {
            flush()
        }
    }

    mutating func flush() {
        guard !buffer.isEmpty else { return }
        print(buffer, terminator: "")
        buffer.removeAll(keepingCapacity: true)
    }
}

func readCapacity() -> Int? {
    while let line = readLine() {
        let trimmed = line.split(separator: " ", omittingEmptySubsequences: true)
        if let token = trimmed.first {
            return Int(token.trimmingSuffix("\r"))
        }
    }
    return nil
}

extension Substring {
    func trimmingSuffix(_ suffix: Character) -> Substring {
        last == suffix ? dropLast() : self
    }
}

func run() {
    guard let capacity = readCapacity(), capacity > 0 else { return }

    var cache = LRUCache<String, String>(capacity: capacity, reservingCapacity: 1 << 16)
    var output = OutputBuffer()

    while let rawLine = readLine() {
        let line = Substring(rawLine).trimmingSuffix("\r")
        let tokens = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard let command = tokens.first else { continue }

        switch command {
        case "SET" where tokens.count >= 3:
            cache.setValue(String(tokens[2]), forKey: String(tokens[1]))
        case "GET" where tokens.count >= 2:
            output.writeLine(cache.value(forKey: String(tokens[1])) ?? "NULL")
        case "DEL" where tokens.count >= 2:
            output.writeLine(cache.removeValue(forKey: String(tokens[1])) ? "1" : "0")
        case "SIZE":
            output.writeLine(String(cache.count))
        default:
            continue
        }
    }

    output.flush()
}

run()
