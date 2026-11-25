/// A single parsed cache command.
public enum Command: Equatable {
    case set(key: Substring, value: Substring)
    case get(key: Substring)
    case delete(key: Substring)
    case size

    /// Parses one input line; returns `nil` for blank or malformed lines.
    public init?(line: Substring) {
        var rest = line[...]
        guard let name = Self.nextToken(&rest) else { return nil }
        let first = Self.nextToken(&rest)
        let second = Self.nextToken(&rest)
        guard Self.nextToken(&rest) == nil else { return nil }

        switch (name, first, second) {
        case let ("SET", key?, value?): self = .set(key: key, value: value)
        case let ("GET", key?, nil): self = .get(key: key)
        case let ("DEL", key?, nil): self = .delete(key: key)
        case ("SIZE", nil, nil): self = .size
        default: return nil
        }
    }

    /// Pops the next space-delimited token off the front of `text`.
    private static func nextToken(_ text: inout Substring) -> Substring? {
        let space = UInt8(ascii: " ")
        let utf8 = text.utf8
        guard let start = utf8.firstIndex(where: { $0 != space }) else {
            text = text[text.endIndex...]
            return nil
        }
        let end = utf8[start...].firstIndex(of: space) ?? utf8.endIndex
        defer { text = text[end...] }
        return text[start..<end]
    }
}

/// Drives an `LRUCache` from textual commands and produces textual output.
public struct CommandProcessor {
    private var cache: LRUCache<String, String>

    public init(capacity: Int) {
        cache = LRUCache(capacity: capacity)
    }

    /// Executes `command`, returning the line to print, if any.
    public mutating func execute(_ command: Command) -> String? {
        switch command {
        case let .set(key, value):
            cache.setValue(String(value), forKey: String(key))
            return nil
        case let .get(key):
            return cache.value(forKey: String(key)) ?? "NULL"
        case let .delete(key):
            return cache.removeValue(forKey: String(key)) ? "1" : "0"
        case .size:
            return String(cache.count)
        }
    }
}

/// Strips a trailing carriage return so CRLF input is handled gracefully.
public func normalizedLine(_ line: String) -> Substring {
    line.utf8.last == UInt8(ascii: "\r") ? line.dropLast() : line[...]
}
