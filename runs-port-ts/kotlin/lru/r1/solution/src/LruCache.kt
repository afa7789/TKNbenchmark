/**
 * A fixed-capacity least-recently-used cache.
 *
 * Backed by an access-ordered [LinkedHashMap]: iteration starts at the least recently used
 * entry, and every lookup or insertion moves the touched entry to the end. All operations
 * run in O(1) expected time.
 */
class LruCache<K : Any, V : Any>(val capacity: Int) {
    init {
        require(capacity >= 1) { "capacity must be a positive integer, got $capacity" }
    }

    private val entries = object : LinkedHashMap<K, V>(initialCapacityFor(capacity), 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>): Boolean = size > capacity
    }

    val size: Int get() = entries.size

    /** Returns the value for [key] and marks it most recently used, or `null` if absent. */
    operator fun get(key: K): V? = entries[key]

    /** Inserts or overwrites [key], marking it most recently used and evicting if over capacity. */
    operator fun set(key: K, value: V) {
        entries[key] = value
    }

    /** Removes [key]; returns whether it was present. */
    fun remove(key: K): Boolean = entries.remove(key) != null

    private companion object {
        /** Presizes for small caches without allocating a huge table up front for large ones. */
        fun initialCapacityFor(capacity: Int): Int = minOf(capacity, 1 shl 16) * 4 / 3 + 1
    }
}
