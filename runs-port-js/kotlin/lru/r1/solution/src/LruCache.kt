/**
 * Fixed-capacity LRU cache. Backed by an access-ordered [LinkedHashMap], so every
 * operation runs in O(1) expected time and the eldest entry is the least recently used.
 */
class LruCache<K, V>(private val capacity: Int) {
    init {
        require(capacity >= 1) { "capacity must be at least 1, was $capacity" }
    }

    private val entries = object : LinkedHashMap<K, V>(initialCapacityFor(capacity), LOAD_FACTOR, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>): Boolean = size > capacity
    }

    val size: Int get() = entries.size

    /** Returns the value for [key], marking it most recently used, or `null` on a miss. */
    operator fun get(key: K): V? = entries[key]

    /** Inserts or overwrites [key], marking it most recently used and evicting if over capacity. */
    operator fun set(key: K, value: V) {
        entries[key] = value
    }

    /** Removes [key]; returns whether it was present. */
    fun remove(key: K): Boolean {
        if (!entries.containsKey(key)) return false
        entries.remove(key)
        return true
    }

    private companion object {
        const val LOAD_FACTOR = 0.75f
        const val MAX_PREALLOCATED = 1 shl 16

        // Pre-size modestly: a huge capacity need not mean a huge working set.
        fun initialCapacityFor(capacity: Int): Int =
            (minOf(capacity, MAX_PREALLOCATED) / LOAD_FACTOR).toInt() + 1
    }
}
