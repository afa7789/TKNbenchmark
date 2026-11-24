import Synchronization

/// Thread-safe in-memory key-value store shared by all connections.
final class KeyValueStore: Sendable {
    private let storage = Mutex<[String: [UInt8]]>([:])

    /// Stores `value` under `key`. Returns `true` if the key was newly created.
    @discardableResult
    func put(_ key: String, value: [UInt8]) -> Bool {
        storage.withLock { $0.updateValue(value, forKey: key) == nil }
    }

    func get(_ key: String) -> [UInt8]? {
        storage.withLock { $0[key] }
    }

    /// Removes `key`. Returns `true` if it was present.
    @discardableResult
    func delete(_ key: String) -> Bool {
        storage.withLock { $0.removeValue(forKey: key) != nil }
    }

    /// All keys in ascending byte-wise order.
    func sortedKeys() -> [String] {
        storage.withLock { Array($0.keys) }
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }
}
