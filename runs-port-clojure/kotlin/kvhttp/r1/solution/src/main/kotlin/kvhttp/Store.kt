package kvhttp

import java.util.concurrent.ConcurrentSkipListMap

/** Thread-safe in-memory key-value store. Keys are kept sorted so listing is cheap. */
class Store {
    private val entries = ConcurrentSkipListMap<String, ByteArray>()

    /** Stores [value] under [key]. Returns true if the key was new. */
    fun put(key: String, value: ByteArray): Boolean = entries.put(key, value) == null

    /** Returns the value stored under [key], or null. */
    fun lookup(key: String): ByteArray? = entries[key]

    /** Removes [key]. Returns true if it was present. */
    fun delete(key: String): Boolean = entries.remove(key) != null

    /** Returns every key in ascending order. */
    fun keys(): List<String> = entries.keys.toList()
}
