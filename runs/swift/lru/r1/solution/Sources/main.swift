/// Reads an LRU capacity followed by cache commands from standard input and
/// writes each command's result to standard output.

/// Collects output lines and flushes them to stdout in large chunks.
struct OutputBuffer {
    private var buffer = ""
    private let flushThreshold = 1 << 16

    mutating func writeLine(_ line: some StringProtocol) {
        buffer.append(contentsOf: line)
        buffer.append("\n")
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

func run() {
    guard let firstLine = readLine(),
          let capacity = Int(firstLine.trimmingSpaces()),
          capacity > 0
    else { return }

    var cache = LRUCache<String, String>(capacity: capacity)
    var output = OutputBuffer()

    while let line = readLine() {
        let tokens = line.split(separator: " ")
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
            continue // Ignore malformed or unknown commands.
        }
    }
    output.flush()
}

extension StringProtocol {
    /// The string with leading and trailing spaces, tabs and carriage returns removed.
    func trimmingSpaces() -> SubSequence {
        let isPadding: (Character) -> Bool = { $0 == " " || $0 == "\t" || $0 == "\r" }
        guard let start = firstIndex(where: { !isPadding($0) }) else { return self[endIndex...] }
        let end = lastIndex(where: { !isPadding($0) })!
        return self[start...end]
    }
}

run()
