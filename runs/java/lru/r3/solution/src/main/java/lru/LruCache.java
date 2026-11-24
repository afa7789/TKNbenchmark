package lru;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * A fixed-capacity cache that evicts the least recently used entry.
 * All operations run in O(1) expected time.
 */
public final class LruCache<K, V> {

    private final Map<K, V> entries;

    public LruCache(int capacity) {
        if (capacity < 1) {
            throw new IllegalArgumentException("capacity must be positive: " + capacity);
        }
        int initial = (int) Math.min((long) capacity * 4 / 3 + 1, 1 << 16);
        this.entries = new LinkedHashMap<>(initial, 0.75f, true) {
            @Override
            protected boolean removeEldestEntry(Map.Entry<K, V> eldest) {
                return size() > capacity;
            }
        };
    }

    /** Inserts or overwrites a mapping, marking the key as most recently used. */
    public void set(K key, V value) {
        entries.put(key, value);
    }

    /** Returns the value for the key (marking it most recently used), or {@code null}. */
    public V get(K key) {
        return entries.get(key);
    }

    /** Removes the key; returns whether it was present. */
    public boolean delete(K key) {
        return entries.remove(key) != null;
    }

    public int size() {
        return entries.size();
    }
}
