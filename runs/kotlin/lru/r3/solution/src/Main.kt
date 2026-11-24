import java.io.BufferedOutputStream
import java.io.InputStream

/** Fixed-capacity LRU cache backed by an access-ordered [LinkedHashMap]; all operations are O(1) expected. */
class LruCache<K, V>(private val capacity: Int) {
    init {
        require(capacity >= 1) { "capacity must be positive: $capacity" }
    }

    private val map = object : LinkedHashMap<K, V>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>?): Boolean = size > capacity
    }

    val size: Int get() = map.size

    operator fun get(key: K): V? = map[key]

    operator fun set(key: K, value: V) {
        map[key] = value
    }

    fun remove(key: K): Boolean = map.remove(key) != null
}

/** Splits a byte buffer into lines, tolerating a missing final newline and CRLF endings. */
private fun InputStream.lines(): Sequence<String> = sequence {
    val bytes = readBytes()
    var start = 0
    while (start < bytes.size) {
        var end = start
        while (end < bytes.size && bytes[end] != '\n'.code.toByte()) end++
        var stop = end
        if (stop > start && bytes[stop - 1] == '\r'.code.toByte()) stop--
        yield(String(bytes, start, stop - start, Charsets.ISO_8859_1))
        start = end + 1
    }
}

fun main() {
    val lines = System.`in`.lines().iterator()
    if (!lines.hasNext()) return
    val capacity = lines.next().trim().toInt()
    val cache = LruCache<String, String>(capacity)
    val out = StringBuilder(1 shl 16)
    val sink = BufferedOutputStream(System.out, 1 shl 16)

    fun flushIfLarge() {
        if (out.length >= 1 shl 16) {
            sink.write(out.toString().toByteArray(Charsets.ISO_8859_1))
            out.setLength(0)
        }
    }

    for (line in lines) {
        if (line.isEmpty()) continue
        val parts = line.split(' ')
        when (parts[0]) {
            "SET" -> if (parts.size >= 3) cache[parts[1]] = parts[2]
            "GET" -> if (parts.size >= 2) out.append(cache[parts[1]] ?: "NULL").append('\n')
            "DEL" -> if (parts.size >= 2) out.append(if (cache.remove(parts[1])) '1' else '0').append('\n')
            "SIZE" -> out.append(cache.size).append('\n')
        }
        flushIfLarge()
    }
    sink.write(out.toString().toByteArray(Charsets.ISO_8859_1))
    sink.flush()
}
