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
        object : LinkedHashMap<K, V>(minOf(capacity, MAX_INITIAL_CAPACITY), 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>?): Boolean = size > capacity
        }

    val size: Int get() = entries.size

    /** Inserts or overwrites a mapping, making the key the most recently used. */
    operator fun set(key: K, value: V) {
        entries[key] = value
    }

    /** Returns the value for the key (marking it most recently used), or `null` if absent. */
    operator fun get(key: K): V? = entries[key]

    /** Removes the key, returning whether it was present. */
    fun remove(key: K): Boolean = entries.remove(key) != null

    private companion object {
        const val MAX_INITIAL_CAPACITY = 1 shl 16
    }
}
