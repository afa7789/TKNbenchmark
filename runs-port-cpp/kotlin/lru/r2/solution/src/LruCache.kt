/**
 * Fixed-capacity least-recently-used cache with O(1) expected-time operations.
 *
 * Backed by an access-ordered [LinkedHashMap]: every successful lookup or
 * overwrite moves the entry to the most-recently-used end, and the eldest
 * entry is evicted once the size exceeds [capacity].
 */
class LruCache<K : Any, V : Any>(val capacity: Int) {
    private val entries = object : LinkedHashMap<K, V>(initialCapacityFor(capacity), LOAD_FACTOR, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>): Boolean = size > capacity
    }

    /** Inserts or overwrites [key], making it the most recently used entry. */
    operator fun set(key: K, value: V) {
        entries[key] = value
    }

    /** Returns the value for [key] and marks it most recently used, or `null` on a miss. */
    operator fun get(key: K): V? = entries[key]

    /** Removes [key]; returns whether it was present. */
    fun remove(key: K): Boolean = entries.remove(key) != null

    val size: Int get() = entries.size

    private companion object {
        const val LOAD_FACTOR = 0.75f

        fun initialCapacityFor(capacity: Int): Int =
            ((capacity.toLong() + 1) / LOAD_FACTOR + 1).toLong().coerceIn(16, 1L shl 30).toInt()
    }
}
