package lru;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * A fixed-capacity cache that evicts the least recently used entry.
 * All operations run in O(1) expected time.
 *
 * @param <K> key type
 * @param <V> value type
 */
public final class LruCache<K, V> {

    private static final int MAX_INITIAL_CAPACITY = 1 << 16;

    private final Map<K, V> entries;

    public LruCache(int capacity) {
        if (capacity < 1) {
            throw new IllegalArgumentException("capacity must be positive: " + capacity);
        }
        int initial = Math.min(capacity, MAX_INITIAL_CAPACITY);
        this.entries = new LinkedHashMap<>(initial, 0.75f, true) {
            @Override
            protected boolean removeEldestEntry(Map.Entry<K, V> eldest) {
                return size() > capacity;
            }
        };
    }

    /** Inserts or overwrites a mapping, making the key the most recently used. */
    public void put(K key, V value) {
        entries.put(key, value);
    }

    /** Returns the value for the key (marking it most recently used), or {@code null} if absent. */
    public V get(K key) {
        return entries.get(key);
    }

    /** Removes the key, returning whether it was present. */
    public boolean remove(K key) {
        return entries.remove(key) != null;
    }

    public int size() {
        return entries.size();
    }
}
