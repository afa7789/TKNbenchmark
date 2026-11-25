package lru;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;

/// A fixed-capacity cache that evicts the least recently used entry once full.
///
/// Every operation runs in O(1) expected time. Not thread-safe.
///
/// @param <K> key type
/// @param <V> value type
public final class LruCache<K, V> {

    private final LinkedHashMap<K, V> entries;

    /// Creates a cache holding at most `capacity` entries.
    ///
    /// @throws IllegalArgumentException if `capacity < 1`
    public LruCache(int capacity) {
        if (capacity < 1) {
            throw new IllegalArgumentException("capacity must be positive: " + capacity);
        }
        // Access order: get/put move the entry to the most-recently-used end.
        this.entries = new LinkedHashMap<>(16, 0.75f, true) {
            @Override
            protected boolean removeEldestEntry(Map.Entry<K, V> eldest) {
                return size() > capacity;
            }
        };
    }

    /// Inserts or overwrites `key`, marking it most recently used; may evict the eldest entry.
    public void put(K key, V value) {
        entries.put(Objects.requireNonNull(key), Objects.requireNonNull(value));
    }

    /// Returns the value for `key`, marking it most recently used, or `null` if absent.
    public V get(K key) {
        return entries.get(key);
    }

    /// Removes `key`, returning whether it was present.
    public boolean remove(K key) {
        return entries.remove(key) != null;
    }

    /// Returns the number of entries currently held.
    public int size() {
        return entries.size();
    }
}
