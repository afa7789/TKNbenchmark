package lru;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * A fixed-capacity least-recently-used cache.
 *
 * <p>Backed by an access-ordered {@link LinkedHashMap}, so lookups, insertions,
 * overwrites and removals all run in O(1) expected time. Both {@link #get} and
 * {@link #put} mark the key as most recently used.
 *
 * <p>Not thread-safe.
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

    /** Returns the value for {@code key}, or {@code null} if absent; a hit refreshes recency. */
    public V get(K key) {
        return entries.get(key);
    }

    /** Inserts or overwrites {@code key}, making it most recently used and evicting if over capacity. */
    public void put(K key, V value) {
        entries.put(key, value);
    }

    /** Removes {@code key}; returns {@code true} if it was present. */
    public boolean remove(K key) {
        return entries.remove(key) != null;
    }

    public int size() {
        return entries.size();
    }
}
