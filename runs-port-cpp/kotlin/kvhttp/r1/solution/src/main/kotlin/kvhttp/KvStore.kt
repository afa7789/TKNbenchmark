package kvhttp

import java.util.concurrent.ConcurrentSkipListMap

/**
 * Thread-safe in-memory key/value store. Keys are kept in ascending order so
 * listing needs no extra sort. Stored arrays are never mutated after insertion,
 * so readers can send them without copying.
 */
class KvStore {
    private val map = ConcurrentSkipListMap<String, ByteArray>()

    /** Returns true if the key was newly inserted, false if it replaced a value. */
    fun put(key: String, value: ByteArray): Boolean = map.put(key, value) == null

    operator fun get(key: String): ByteArray? = map[key]

    /** Returns true if the key existed. */
    fun remove(key: String): Boolean = map.remove(key) != null

    /** Keys in ascending order (keys are ASCII, so this is byte-wise order). */
    fun keys(): List<String> = map.keys.toList()
}
