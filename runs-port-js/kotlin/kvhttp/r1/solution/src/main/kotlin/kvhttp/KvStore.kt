package kvhttp

import java.util.concurrent.ConcurrentHashMap

/** Thread-safe in-memory map from key to raw value bytes. */
class KvStore {
    private val entries = ConcurrentHashMap<String, ByteArray>()

    operator fun get(key: String): ByteArray? = entries[key]

    /** Stores [value] under [key]; returns true if the key was not present before. */
    fun put(key: String, value: ByteArray): Boolean = entries.put(key, value) == null

    /** Removes [key]; returns true if it was present. */
    fun remove(key: String): Boolean = entries.remove(key) != null

    fun sortedKeys(): List<String> = entries.keys.sorted()
}
