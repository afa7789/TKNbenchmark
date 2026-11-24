import os

/// Thread-safe in-memory key-value store shared by all connection threads.
final class KeyValueStore: Sendable {
    enum PutResult {
        case created
        case replaced
    }

    private let storage = OSAllocatedUnfairLock<[String: [UInt8]]>(initialState: [:])

    func get(_ key: String) -> [UInt8]? {
        storage.withLock { $0[key] }
    }

    func put(_ key: String, value: [UInt8]) -> PutResult {
        storage.withLock { $0.updateValue(value, forKey: key) == nil ? .created : .replaced }
    }

    /// Returns `true` if the key existed and was removed.
    func delete(_ key: String) -> Bool {
        storage.withLock { $0.removeValue(forKey: key) != nil }
    }

    /// All keys, sorted ascending by byte value.
    func sortedKeys() -> [String] {
        let keys = storage.withLock { Array($0.keys) }
        return keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }
}
