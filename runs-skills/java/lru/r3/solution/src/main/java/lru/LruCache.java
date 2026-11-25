package lru;

import java.util.LinkedHashMap;
import java.util.Map;

/// A fixed-capacity cache that evicts the least recently used entry.
///
/// Backed by an access-ordered [LinkedHashMap], so every operation runs in O(1) expected time.
/// Both lookups and writes (including overwrites) mark a key as the most recently used.
/// Not thread-safe.
///
/// @param <K> key type
/// @param <V> value type
public final class LruCache<K, V> {

    private final Map<K, V> entries;

    /// Creates a cache holding at most `capacity` entries.
    ///
    /// @throws IllegalArgumentException if `capacity` is not positive
    public LruCache(int capacity) {
        if (capacity <= 0) {
            throw new IllegalArgumentException("capacity must be positive: " + capacity);
        }
        this.entries = new BoundedAccessOrderMap<>(capacity);
    }

    /// Inserts or overwrites `key`, making it the most recently used and evicting the
    /// least recently used entry if the capacity is exceeded.
    public void put(K key, V value) {
        entries.put(key, value);
    }

    /// Returns the value for `key`, or `null` on a miss. A hit makes the key the most recently used.
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

    private static final class BoundedAccessOrderMap<K, V> extends LinkedHashMap<K, V> {
        private static final long serialVersionUID = 1L;

        private final int capacity;

        BoundedAccessOrderMap(int capacity) {
            // Pre-size for small capacities only; large ones grow on demand.
            super(Math.min(capacity, 1 << 16) * 4 / 3 + 1, 0.75f, true);
            this.capacity = capacity;
        }

        @Override
        protected boolean removeEldestEntry(Map.Entry<K, V> eldest) {
            return size() > capacity;
        }
    }
}
