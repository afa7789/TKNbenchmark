import Synchronization

/// Thread-safe in-memory key-value storage shared by all connections.
final class KeyValueStore: Sendable {
    enum PutOutcome: Sendable {
        case created
        case replaced
    }

    private let storage = Mutex<[String: [UInt8]]>([:])

    func get(_ key: String) -> [UInt8]? {
        storage.withLock { $0[key] }
    }

    @discardableResult
    func put(_ key: String, value: [UInt8]) -> PutOutcome {
        storage.withLock { $0.updateValue(value, forKey: key) == nil ? .created : .replaced }
    }

    /// Returns `true` if a value was removed.
    @discardableResult
    func delete(_ key: String) -> Bool {
        storage.withLock { $0.removeValue(forKey: key) != nil }
    }

    /// All keys, sorted ascending by byte value.
    func sortedKeys() -> [String] {
        let keys = storage.withLock { Array($0.keys) }
        return keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }
}
