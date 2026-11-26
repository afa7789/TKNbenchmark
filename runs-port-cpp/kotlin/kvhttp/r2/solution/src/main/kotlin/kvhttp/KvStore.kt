package kvhttp

import java.util.TreeMap
import java.util.concurrent.locks.ReentrantReadWriteLock
import kotlin.concurrent.read
import kotlin.concurrent.write

/**
 * Thread-safe in-memory key-value store. Keys are kept ordered so that
 * listing them sorted is a linear walk.
 */
class KvStore {
    enum class PutResult { CREATED, REPLACED }

    private val lock = ReentrantReadWriteLock()
    private val data = TreeMap<String, ByteArray>()

    fun put(key: String, value: ByteArray): PutResult = lock.write {
        if (data.put(key, value) == null) PutResult.CREATED else PutResult.REPLACED
    }

    operator fun get(key: String): ByteArray? = lock.read { data[key] }

    fun remove(key: String): Boolean = lock.write { data.remove(key) != null }

    fun keys(): List<String> = lock.read { data.keys.toList() }
}
