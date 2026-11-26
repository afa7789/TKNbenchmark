package lru

/**
 * A fixed-capacity cache that evicts the least recently used entry.
 * All operations run in O(1) expected time.
 */
class LruCache<K : Any, V : Any>(private val capacity: Int) {

    init {
        require(capacity >= 1) { "capacity must be positive: $capacity" }
    }

    private val entries: MutableMap<K, V> =
        object : LinkedHashMap<K, V>(minOf(capacity.toLong() * 4 / 3 + 1, 1L shl 16).toInt(), 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>?): Boolean = size > capacity
        }

    /** Inserts or overwrites a mapping, marking the key as most recently used. */
    operator fun set(key: K, value: V) {
        entries[key] = value
    }

    /** Returns the value for the key (marking it most recently used), or `null`. */
    operator fun get(key: K): V? = entries[key]

    /** Removes the key; returns whether it was present. */
    fun delete(key: K): Boolean = entries.remove(key) != null

    val size: Int get() = entries.size
}
