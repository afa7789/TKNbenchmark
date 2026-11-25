/**
 * Fixed-capacity cache that evicts the least recently used entry once it holds more than [capacity] keys.
 * Backed by an access-ordered [LinkedHashMap], so every operation runs in O(1) expected time.
 */
class LruCache<K : Any, V : Any>(private val capacity: Int) {
    init {
        require(capacity >= 1) { "capacity must be positive, was $capacity" }
    }

    private val entries = object : LinkedHashMap<K, V>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>): Boolean = size > capacity
    }

    val size: Int get() = entries.size

    /** Returns the value for [key] and marks it most recently used, or `null` on a miss. */
    operator fun get(key: K): V? = entries[key]

    /** Inserts or overwrites [key], marks it most recently used and evicts if over capacity. */
    operator fun set(key: K, value: V) {
        entries[key] = value
    }

    /** Removes [key]; returns whether it was present. */
    fun remove(key: K): Boolean = entries.remove(key) != null
}
