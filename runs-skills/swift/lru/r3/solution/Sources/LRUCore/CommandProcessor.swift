/// Interprets the line-oriented LRU command language.
public struct CommandProcessor {
    private var cache: LRUCache<String, String>

    public init(capacity: Int) {
        cache = LRUCache(capacity: capacity)
    }

    /// Parses the capacity header line, returning `nil` if it is invalid.
    public static func parseCapacity(_ line: some StringProtocol) -> Int? {
        guard let value = Int(String(line.filter { !$0.isWhitespace })), value >= 1 else { return nil }
        return value
    }

    /// Executes one command line, returning the output line it produces, if any.
    /// Unrecognized or malformed lines produce no output.
    public mutating func execute(_ line: Substring) -> String? {
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
        guard let command = tokens.first else { return nil }
        switch (command, tokens.count) {
        case ("SET", 3):
            cache.set(String(tokens[1]), String(tokens[2]))
            return nil
        case ("GET", 2):
            return cache.get(String(tokens[1])) ?? "NULL"
        case ("DEL", 2):
            return cache.remove(String(tokens[1])) ? "1" : "0"
        case ("SIZE", 1):
            return String(cache.count)
        default:
            return nil
        }
    }
}
