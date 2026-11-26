package kvhttp

import java.util.concurrent.ConcurrentSkipListMap

/** Outcome of [Store.put]. */
enum class PutResult { CREATED, REPLACED }

/** Thread-safe in-memory key-value store that keeps its keys sorted. */
class Store {
    private val entries = ConcurrentSkipListMap<String, ByteArray>()

    /** Returns the value stored under [key], or null. */
    operator fun get(key: String): ByteArray? = entries[key]

    /** Stores [value] under [key], reporting whether the key was new. */
    fun put(key: String, value: ByteArray): PutResult =
        if (entries.put(key, value) == null) PutResult.CREATED else PutResult.REPLACED

    /** Removes [key]. Returns true if it was present. */
    fun delete(key: String): Boolean = entries.remove(key) != null

    /** Every key, sorted ascending. */
    fun keys(): List<String> = entries.keys.toList()
}
