package kvhttp;

import java.util.List;
import java.util.Optional;
import java.util.concurrent.ConcurrentNavigableMap;
import java.util.concurrent.ConcurrentSkipListMap;

/// Thread-safe in-memory store mapping keys to byte values, iterable in key order.
final class KeyValueStore {

    private final ConcurrentNavigableMap<String, byte[]> entries = new ConcurrentSkipListMap<>();

    /// Stores `value` under `key`; returns `true` if the key did not exist before.
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

    /// Returns a snapshot of all keys in ascending order.
    List<String> keys() {
        return List.copyOf(entries.keySet());
    }
}
