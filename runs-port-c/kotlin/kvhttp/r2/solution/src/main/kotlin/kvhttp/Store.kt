package kvhttp

import java.util.concurrent.ConcurrentSkipListMap

/** Maximum key length accepted by the store. */
const val KEY_MAX_LENGTH = 64

private val KEY_PATTERN = Regex("[A-Za-z0-9_-]{1,$KEY_MAX_LENGTH}")

fun isValidKey(key: String): Boolean = KEY_PATTERN.matches(key)

/**
 * Thread-safe in-memory key-value store.
 *
 * Values are treated as immutable once stored: callers hand over ownership of the
 * array on [put] and must not modify arrays returned by [get].
 */
class KeyValueStore {
    // A skip list keeps keys ordered, so listing never needs a separate sort.
    // Keys are ASCII, so String ordering matches byte ordering.
    private val entries = ConcurrentSkipListMap<String, ByteArray>()

    /** Stores [value] under [key]; returns true if the key was new. */
    fun put(key: String, value: ByteArray): Boolean = entries.put(key, value) == null

    fun get(key: String): ByteArray? = entries[key]

    /** Returns true if the key existed and was removed. */
    fun delete(key: String): Boolean = entries.remove(key) != null

    /** Snapshot of all keys, sorted ascending. */
    fun keys(): List<String> = entries.keys.toList()
}
