package lru

/**
 * A fixed-capacity least-recently-used cache.
 *
 * Backed by an access-ordered [LinkedHashMap], so lookups, insertions, overwrites and
 * removals all run in O(1) expected time. Both [get] and [set] mark the key as most
 * recently used.
 *
 * Not thread-safe.
 */
class LruCache<K : Any, V : Any>(val capacity: Int) {

    init {
        require(capacity >= 1) { "capacity must be positive: $capacity" }
    }

    private val entries = object : LinkedHashMap<K, V>(capacity.coerceAtMost(MAX_INITIAL_CAPACITY), 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>): Boolean = size > capacity
    }

    /** Number of keys currently held. */
    val size: Int get() = entries.size

    /** Returns the value for [key], or `null` if absent; a hit refreshes recency. */
    operator fun get(key: K): V? = entries[key]

    /** Inserts or overwrites [key], making it most recently used and evicting if over capacity. */
    operator fun set(key: K, value: V) {
        entries[key] = value
    }

    /** Removes [key]; returns `true` if it was present. */
    fun remove(key: K): Boolean = entries.remove(key) != null

    private companion object {
        const val MAX_INITIAL_CAPACITY = 1 shl 16
    }
}
