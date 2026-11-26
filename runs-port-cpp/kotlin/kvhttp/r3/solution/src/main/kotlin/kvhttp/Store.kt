package kvhttp

import java.util.concurrent.ConcurrentSkipListMap

/**
 * Thread-safe in-memory key/value store. Values are immutable once stored, so
 * readers can hand them straight to the network layer without copying.
 */
class Store {
    private val data = ConcurrentSkipListMap<String, ByteArray>()

    /** Stores [value] under [key]; returns true if the key was newly created. */
    fun put(key: String, value: ByteArray): Boolean = data.put(key, value) == null

    operator fun get(key: String): ByteArray? = data[key]

    /** Removes [key]; returns true if it was present. */
    fun remove(key: String): Boolean = data.remove(key) != null

    /** Keys in ascending order (keys are ASCII, so this is also byte order). */
    fun keys(): List<String> = data.keys.toList()
}
