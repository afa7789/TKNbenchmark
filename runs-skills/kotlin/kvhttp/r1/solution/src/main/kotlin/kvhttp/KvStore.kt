package kvhttp

import java.util.concurrent.ConcurrentHashMap

/** Thread-safe in-memory key-value store. */
class KvStore {
    private val entries = ConcurrentHashMap<String, ByteArray>()

    /** Stores [value] under [key]; returns true if the key was new. */
    fun put(key: String, value: ByteArray): Boolean = entries.put(key, value) == null

    operator fun get(key: String): ByteArray? = entries[key]

    /** Removes [key]; returns true if it was present. */
    fun delete(key: String): Boolean = entries.remove(key) != null

    fun sortedKeys(): List<String> = entries.keys.sorted()
}
