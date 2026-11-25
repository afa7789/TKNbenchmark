package kvhttp;

import java.util.List;
import java.util.Optional;
import java.util.concurrent.ConcurrentNavigableMap;
import java.util.concurrent.ConcurrentSkipListMap;

/// Thread-safe in-memory store of byte values, keyed and iterated in ascending key order.
final class KeyValueStore {

    private final ConcurrentNavigableMap<String, byte[]> entries = new ConcurrentSkipListMap<>();

    /// Stores `value` under `key`; returns `true` if the key was not present before.
    boolean put(String key, byte[] value) {
        return entries.put(key, value) == null;
    }

    Optional<byte[]> get(String key) {
        return Optional.ofNullable(entries.get(key));
    }

    /// Removes `key`; returns `true` if it was present.
    boolean delete(String key) {
        return entries.remove(key) != null;
    }

    /// Snapshot of all keys, sorted ascending.
    List<String> keys() {
        return List.copyOf(entries.keySet());
    }
}
