import Foundation
import Synchronization

/// Thread-safe in-memory key-value store.
public final class KVStore: Sendable {
    private let storage = Mutex<[String: Data]>([:])

    public init() {}

    /// Stores `value` under `key`. Returns `true` if the key was newly created.
    @discardableResult
    public func put(_ key: String, _ value: Data) -> Bool {
        storage.withLock { $0.updateValue(value, forKey: key) == nil }
    }

    public func get(_ key: String) -> Data? {
        storage.withLock { $0[key] }
    }

    /// Removes `key`. Returns `true` if it was present.
    @discardableResult
    public func delete(_ key: String) -> Bool {
        storage.withLock { $0.removeValue(forKey: key) != nil }
    }

    /// All keys, sorted ascending.
    public func keys() -> [String] {
        storage.withLock { Array($0.keys) }.sorted()
    }
}
