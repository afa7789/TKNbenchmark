package kvhttp

import java.util.concurrent.ConcurrentSkipListMap

/** Thread-safe in-memory key-value store holding raw byte values. */
class KvStore {
    private val data = ConcurrentSkipListMap<String, ByteArray>()

    /** Stores [value] under [key]; returns true if the key was newly created. */
    fun put(key: String, value: ByteArray): Boolean = data.put(key, value) == null

    operator fun get(key: String): ByteArray? = data[key]

    /** Removes [key]; returns true if it was present. */
    fun delete(key: String): Boolean = data.remove(key) != null

    /** All keys sorted ascending (keys are ASCII, so natural order matches code-unit order). */
    fun keys(): List<String> = data.keys.toList()
}
