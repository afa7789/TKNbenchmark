package lru;

import java.util.LinkedHashMap;
import java.util.Map;

/// A fixed-capacity cache that evicts the least recently used entry.
///
/// Both reads ({@link #get}) and writes ({@link #put}) count as a use. All operations run in
/// O(1) expected time. Not thread-safe.
public final class LruCache<K, V> {

    private final Map<K, V> entries;

    public LruCache(int capacity) {
        if (capacity < 1) {
            throw new IllegalArgumentException("capacity < 1: " + capacity);
        }
        // Access-ordered map: iteration order runs from least to most recently used.
        this.entries = new LinkedHashMap<>(initialTableSize(capacity), 0.75f, true) {
            @Override
            protected boolean removeEldestEntry(Map.Entry<K, V> eldest) {
                return size() > capacity;
            }
        };
    }

    private static int initialTableSize(int capacity) {
        // Pre-size modestly; the map grows on demand for large capacities.
        return Math.min(capacity, 1 << 16) * 4 / 3 + 1;
    }

    /// Inserts or overwrites the value for `key`, making it the most recently used.
    public void put(K key, V value) {
        entries.put(key, value);
    }

    /// Returns the value for `key`, or `null` if absent. A hit makes the key most recently used.
    public V get(K key) {
        return entries.get(key);
    }

    /// Removes `key`; returns whether it was present.
    public boolean remove(K key) {
        return entries.remove(key) != null;
    }

    public int size() {
        return entries.size();
    }
}
