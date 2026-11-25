package kvhttp

import java.util.concurrent.ConcurrentSkipListMap

/** Thread-safe in-memory key-value store whose keys are kept in ascending order. */
class KvStore {
    private val entries = ConcurrentSkipListMap<String, ByteArray>()

    /** Stores [value] under [key]; returns `true` if the key was not present before. */
    fun put(key: String, value: ByteArray): Boolean = entries.put(key, value) == null

    operator fun get(key: String): ByteArray? = entries[key]

    /** Removes [key]; returns `true` if it was present. */
    fun delete(key: String): Boolean = entries.remove(key) != null

    /** All keys, sorted ascending. */
    fun keys(): List<String> = entries.keys.toList()
}
