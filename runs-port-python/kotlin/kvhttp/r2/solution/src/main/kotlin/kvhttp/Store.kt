package kvhttp

import java.util.concurrent.ConcurrentSkipListMap

/** Thread-safe in-memory key-value store whose keys are kept in ascending order. */
class Store {
    private val data = ConcurrentSkipListMap<String, ByteArray>()

    /** Stores [value] under [key]; returns true if the key was new. */
    fun put(key: String, value: ByteArray): Boolean = data.put(key, value) == null

    fun get(key: String): ByteArray? = data[key]

    /** Removes [key]; returns true if it was present. */
    fun delete(key: String): Boolean = data.remove(key) != null

    /** A snapshot of every key, sorted ascending. */
    fun keys(): List<String> = data.keys.toList()
}
