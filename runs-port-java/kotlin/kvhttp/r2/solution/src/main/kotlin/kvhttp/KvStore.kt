package kvhttp

import java.util.concurrent.ConcurrentSkipListMap

/** Thread-safe in-memory store keeping keys in ascending order. */
class KvStore {
    private val entries = ConcurrentSkipListMap<String, ByteArray>()

    /** Stores [value] under [key]; returns `true` if the key was newly created. */
    fun put(key: String, value: ByteArray): Boolean = entries.put(key, value) == null

    operator fun get(key: String): ByteArray? = entries[key]

    /** Removes [key]; returns `true` if it was present. */
    fun delete(key: String): Boolean = entries.remove(key) != null

    /** A snapshot of all keys in ascending order. */
    fun keys(): List<String> = entries.keys.toList()
}
