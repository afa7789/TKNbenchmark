package kvhttp

import java.util.concurrent.ConcurrentHashMap

/** Thread-safe in-memory key-value store holding raw byte values. */
class KvStore {
    private val data = ConcurrentHashMap<String, ByteArray>()

    operator fun get(key: String): ByteArray? = data[key]

    /** Stores [value] under [key]; returns true if the key was newly created. */
    fun set(key: String, value: ByteArray): Boolean = data.put(key, value) == null

    fun delete(key: String): Boolean = data.remove(key) != null

    /** All keys sorted ascending (byte order for valid, ASCII-only keys). */
    fun keys(): List<String> = data.keys.sorted()
}
