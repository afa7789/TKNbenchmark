package kvhttp

import java.util.concurrent.ConcurrentHashMap

/** Thread-safe in-memory key-value store. Values are kept as raw bytes. */
class KvStore {
    private val entries = ConcurrentHashMap<String, ByteArray>()

    /** Stores [value] under [key]; returns true if the key was newly created. */
    fun set(key: String, value: ByteArray): Boolean = entries.put(key, value) == null

    operator fun get(key: String): ByteArray? = entries[key]

    /** Removes [key]; returns true if it was present. */
    fun delete(key: String): Boolean = entries.remove(key) != null

    /** All keys in ascending (code-unit) order. */
    fun keys(): List<String> = entries.keys.sorted()
}
