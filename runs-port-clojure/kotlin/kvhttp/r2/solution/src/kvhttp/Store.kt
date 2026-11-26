package kvhttp

import java.util.concurrent.ConcurrentSkipListMap

/** Outcome of [Store.put]. */
enum class PutResult { CREATED, REPLACED }

/**
 * Thread-safe in-memory key-value store. Keys are kept sorted so listing is a
 * cheap traversal.
 */
class Store {
    private val entries = ConcurrentSkipListMap<String, ByteArray>()

    fun put(key: String, value: ByteArray): PutResult =
        if (entries.put(key, value) == null) PutResult.CREATED else PutResult.REPLACED

    fun get(key: String): ByteArray? = entries[key]

    /** Removes [key]; returns true if it was present. */
    fun delete(key: String): Boolean = entries.remove(key) != null

    /** All keys in ascending order. */
    fun keys(): List<String> = entries.keys.toList()
}
