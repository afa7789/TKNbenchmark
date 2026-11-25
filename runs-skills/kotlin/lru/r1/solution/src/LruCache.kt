/**
 * Fixed-capacity cache that evicts the least recently used entry once it would exceed [capacity].
 * Every operation runs in O(1) expected time.
 */
class LruCache<K : Any, V : Any>(val capacity: Int) {
    init {
        require(capacity >= 1) { "capacity must be at least 1, was $capacity" }
    }

    // Access-ordered map: iteration starts at the least recently used entry.
    private val entries = object : LinkedHashMap<K, V>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>): Boolean = size > capacity
    }

    val size: Int get() = entries.size

    /** Inserts or overwrites [key], making it the most recently used. */
    operator fun set(key: K, value: V) {
        entries[key] = value
    }

    /** Returns the value for [key], marking it most recently used on a hit. */
    operator fun get(key: K): V? = entries[key]

    /** Removes [key]; returns whether it was present. */
    fun remove(key: K): Boolean = entries.remove(key) != null
}
