/// Reads a capacity followed by cache commands from standard input and
/// writes each command's result to standard output.

/// Buffers output and flushes it in large chunks to keep I/O cheap.
struct OutputBuffer {
    private var buffer = ""
    private let flushThreshold = 1 << 16

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

extension String {
    /// Splits the string on ASCII spaces, dropping empty tokens and a trailing
    /// carriage return. Works on UTF-8 code units, avoiding the cost of
    /// grapheme-cluster segmentation.
    func asciiTokens() -> [Substring] {
        let space = UInt8(ascii: " ")
        let utf8 = self.utf8
        var end = utf8.endIndex
        if let last = utf8.indices.last, utf8[last] == UInt8(ascii: "\r") {
            end = last
        }
        var tokens: [Substring] = []
        tokens.reserveCapacity(3)
        var cursor = utf8.startIndex
        while cursor < end {
            if utf8[cursor] == space {
                cursor = utf8.index(after: cursor)
                continue
            }
            let tokenEnd = utf8[cursor..<end].firstIndex(of: space) ?? end
            tokens.append(self[cursor..<tokenEnd])
            cursor = tokenEnd
        }
        return tokens
    }
}

func run() {
    guard let firstLine = readLine(),
          let first = firstLine.asciiTokens().first,
          let capacity = Int(first),
          capacity > 0
    else { return }

    var cache = LRUCache<String, String>(capacity: capacity)
    var output = OutputBuffer()

    while let line = readLine() {
        let tokens = line.asciiTokens()
        guard let command = tokens.first else { continue }

        switch (command, tokens.count) {
        case ("SET", 3):
            cache.setValue(String(tokens[2]), forKey: String(tokens[1]))
        case ("GET", 2):
            output.writeLine(cache.value(forKey: String(tokens[1])) ?? "NULL")
        case ("DEL", 2):
            output.writeLine(cache.removeValue(forKey: String(tokens[1])) ? "1" : "0")
        case ("SIZE", 1):
            output.writeLine(String(cache.count))
        default:
            continue  // Ignore malformed commands.
        }
    }
    output.flush()
}

run()
