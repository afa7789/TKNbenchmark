package kvhttp;

import java.util.List;
import java.util.Optional;
import java.util.concurrent.ConcurrentNavigableMap;
import java.util.concurrent.ConcurrentSkipListMap;

/** Thread-safe in-memory key-value store with keys kept in ascending order. */
final class KvStore {

    private final ConcurrentNavigableMap<String, byte[]> entries = new ConcurrentSkipListMap<>();

    /**
     * Stores {@code value} under {@code key}.
     *
     * @return {@code true} if the key was new, {@code false} if an existing value was replaced
     */
    boolean put(String key, byte[] value) {
        return entries.put(key, value) == null;
    }

    Optional<byte[]> get(String key) {
        return Optional.ofNullable(entries.get(key));
    }

    /** @return {@code true} if the key was present and has been removed */
    boolean delete(String key) {
        return entries.remove(key) != null;
    }

    /** @return a snapshot of all keys in ascending order */
    List<String> keys() {
        return List.copyOf(entries.keySet());
    }
}
