package kvhttp;

import java.util.List;
import java.util.Optional;
import java.util.concurrent.ConcurrentNavigableMap;
import java.util.concurrent.ConcurrentSkipListMap;

/** Thread-safe in-memory store keeping keys in ascending order. */
final class KvStore {
    private final ConcurrentNavigableMap<String, byte[]> entries = new ConcurrentSkipListMap<>();

    /** Stores the value; returns {@code true} if the key was newly created. */
    boolean put(String key, byte[] value) {
        return entries.put(key, value) == null;
    }

    Optional<byte[]> get(String key) {
        return Optional.ofNullable(entries.get(key));
    }

    /** Removes the key; returns {@code true} if it was present. */
    boolean delete(String key) {
        return entries.remove(key) != null;
    }

    List<String> keys() {
        return List.copyOf(entries.keySet());
    }
}
