package lru

/**
 * Fixed-capacity cache that evicts the least recently used key once it holds
 * more than [capacity] entries. Every operation runs in O(1) expected time.
 *
 * [expectedEntries] is a sizing hint only: storage is preallocated for
 * `min(capacity, expectedEntries)` entries and grows on demand.
 */
class LruCache<K, V>(private val capacity: Long, expectedEntries: Int = DEFAULT_EXPECTED) {
    init {
        require(capacity > 0) { "capacity must be positive, was $capacity" }
    }

    private val entries = object : LinkedHashMap<K, V>(
        initialCapacityFor(minOf(capacity, expectedEntries.toLong()).toInt()),
        LOAD_FACTOR,
        /* accessOrder = */ true,
    ) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>?): Boolean = size > capacity
    }

    val size: Int get() = entries.size

    /** Inserts or overwrites [key]; it becomes the most recently used. */
    operator fun set(key: K, value: V) {
        entries[key] = value
    }

    /** Returns the value for [key] and marks it most recently used, or `null` on a miss. */
    operator fun get(key: K): V? = entries[key]

    /** Removes [key]; returns `true` if it was present. */
    fun remove(key: K): Boolean {
        if (!entries.containsKey(key)) return false
        entries.remove(key)
        return true
    }

    private companion object {
        const val DEFAULT_EXPECTED = 16
        const val LOAD_FACTOR = 0.75f

        fun initialCapacityFor(entries: Int): Int =
            (entries.coerceAtLeast(1) / LOAD_FACTOR).toLong().coerceAtMost(1L shl 30).toInt() + 1
    }
}
