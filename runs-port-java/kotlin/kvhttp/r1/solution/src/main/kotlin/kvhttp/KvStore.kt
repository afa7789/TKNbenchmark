package kvhttp

import java.util.concurrent.ConcurrentSkipListMap

/** Thread-safe in-memory key-value store with keys kept in ascending order. */
class KvStore {
    private val entries = ConcurrentSkipListMap<String, ByteArray>()

    /** Stores [value] under [key]; returns `true` if the key was new, `false` if a value was replaced. */
    fun put(key: String, value: ByteArray): Boolean = entries.put(key, value) == null

    operator fun get(key: String): ByteArray? = entries[key]

    /** Returns `true` if the key was present and has been removed. */
    fun delete(key: String): Boolean = entries.remove(key) != null

    /** Returns a snapshot of all keys in ascending order. */
    fun keys(): List<String> = entries.keys.toList()
}
