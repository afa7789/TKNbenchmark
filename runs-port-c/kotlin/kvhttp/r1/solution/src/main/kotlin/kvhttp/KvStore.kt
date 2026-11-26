package kvhttp

import java.util.concurrent.ConcurrentHashMap

/**
 * Thread-safe in-memory key-value store. Values are arbitrary byte sequences.
 *
 * Stored arrays are never mutated after insertion, so they can be handed out
 * to readers without copying.
 */
class KvStore {
    private val entries = ConcurrentHashMap<String, ByteArray>()

    /** Stores [value] under [key]; returns `true` if the key was new, `false` if it replaced a value. */
    fun put(key: String, value: ByteArray): Boolean = entries.put(key, value) == null

    fun get(key: String): ByteArray? = entries[key]

    /** Returns `true` if the key was present and has been removed. */
    fun delete(key: String): Boolean = entries.remove(key) != null

    /** A snapshot of all keys, sorted ascending. */
    fun sortedKeys(): List<String> = entries.keys.sorted()
}
