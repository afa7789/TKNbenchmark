import Synchronization

/// Thread-safe in-memory key-value store.
public final class KVStore: Sendable {
    public enum PutResult: Sendable, Equatable {
        case created
        case replaced
    }

    private let storage = Mutex<[String: [UInt8]]>([:])

    public init() {}

    @discardableResult
    public func put(_ key: String, value: [UInt8]) -> PutResult {
        storage.withLock { $0.updateValue(value, forKey: key) == nil ? .created : .replaced }
    }

    public func get(_ key: String) -> [UInt8]? {
        storage.withLock { $0[key] }
    }

    /// Returns `true` if the key existed.
    @discardableResult
    public func delete(_ key: String) -> Bool {
        storage.withLock { $0.removeValue(forKey: key) != nil }
    }

    public func sortedKeys() -> [String] {
        storage.withLock { Array($0.keys) }.sorted()
    }
}
