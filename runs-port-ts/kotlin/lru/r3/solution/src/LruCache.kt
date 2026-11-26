package lru

/**
 * Fixed-capacity LRU cache with O(1) expected-time operations.
 *
 * Backed by an access-ordered [LinkedHashMap]: every successful lookup or
 * overwrite moves the entry to the most-recently-used end, and the eldest
 * entry is evicted once the size exceeds [capacity].
 */
class LruCache<K : Any, V : Any>(val capacity: Int) {
    init {
        require(capacity >= 1) { "capacity must be a positive integer, got $capacity" }
    }

    private val entries = object : LinkedHashMap<K, V>(initialTableSize(capacity), LOAD_FACTOR, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>): Boolean = size > capacity
    }

    val size: Int get() = entries.size

    /** Returns the value for [key], marking it most recently used, or `null` if absent. */
    operator fun get(key: K): V? = entries[key]

    /** Inserts or overwrites [key], marking it most recently used and evicting if over capacity. */
    operator fun set(key: K, value: V) {
        entries[key] = value
    }

    /** Removes [key]; returns whether it was present. */
    fun remove(key: K): Boolean = entries.remove(key) != null

    private companion object {
        const val LOAD_FACTOR = 0.75f

        // Size the table up front so the map never rehashes, capped to avoid huge eager allocations.
        fun initialTableSize(capacity: Int): Int =
            (minOf(capacity, 1 shl 20) / LOAD_FACTOR).toInt() + 1
    }
}
