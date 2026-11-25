/// Interprets the line-oriented LRU command language and accumulates output.
public struct CommandProcessor {
    private var cache: LRUCache<String, String>
    public private(set) var output = ""

    public init(capacity: Int) {
        cache = LRUCache(capacity: capacity)
    }

    /// Executes one command line. Blank or unrecognised lines are ignored.
    public mutating func execute(_ line: Substring) {
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
        guard let command = tokens.first else { return }
        switch (command, tokens.count) {
        case ("SET", 3):
            cache.set(String(tokens[1]), String(tokens[2]))
        case ("GET", 2):
            emit(cache.get(String(tokens[1])) ?? "NULL")
        case ("DEL", 2):
            emit(cache.remove(String(tokens[1])) ? "1" : "0")
        case ("SIZE", 1):
            emit(String(cache.count))
        default:
            break
        }
    }

    private mutating func emit(_ text: some StringProtocol) {
        output += text
        output += "\n"
    }
}

extension CommandProcessor {
    /// Runs a complete program: the first line is the capacity, the rest are commands.
    /// Returns `nil` if the capacity line is missing or invalid.
    public static func run(lines: some Sequence<Substring>) -> String? {
        var iterator = lines.makeIterator()
        guard let first = iterator.next(),
              let capacity = Int(first.trimmingWhitespace()),
              capacity >= 1
        else { return nil }
        var processor = CommandProcessor(capacity: capacity)
        while let line = iterator.next() {
            processor.execute(line)
        }
        return processor.output
    }
}

extension Substring {
    func trimmingWhitespace() -> Substring {
        let isSpace: (Character) -> Bool = { $0 == " " || $0 == "\t" || $0 == "\r" }
        let start = firstIndex { !isSpace($0) } ?? endIndex
        let end = lastIndex { !isSpace($0) }.map(index(after:)) ?? start
        return self[start..<end]
    }
}
