import Synchronization

/// Thread-safe in-memory key-value store.
public final class KVStore: Sendable {
    private let entries = Mutex<[String: [UInt8]]>([:])

    public init() {}

    /// Stores `value` under `key`. Returns `true` if the key did not exist before.
    @discardableResult
    public func put(_ key: String, _ value: [UInt8]) -> Bool {
        entries.withLock { $0.updateValue(value, forKey: key) == nil }
    }

    public func get(_ key: String) -> [UInt8]? {
        entries.withLock { $0[key] }
    }

    /// Removes `key`. Returns `true` if it was present.
    @discardableResult
    public func delete(_ key: String) -> Bool {
        entries.withLock { $0.removeValue(forKey: key) != nil }
    }

    /// All keys, sorted ascending.
    public func keys() -> [String] {
        entries.withLock { Array($0.keys) }.sorted()
    }
}
