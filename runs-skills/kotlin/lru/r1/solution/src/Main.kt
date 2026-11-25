import java.io.BufferedWriter
import java.io.OutputStreamWriter

private const val OUTPUT_BUFFER = 1 shl 16

fun main() {
    val reader = System.`in`.bufferedReader(Charsets.US_ASCII)
    val out = BufferedWriter(OutputStreamWriter(System.out, Charsets.US_ASCII), OUTPUT_BUFFER)

    val capacity = reader.readLine()?.trim()?.toIntOrNull() ?: return
    val cache = LruCache<String, String>(capacity)

    out.use {
        reader.lineSequence().forEach { line -> execute(line.trimEnd('\r'), cache, out) }
    }
}

private fun execute(line: String, cache: LruCache<String, String>, out: Appendable) {
    val parts = line.split(' ')
    when (parts[0]) {
        "SET" -> if (parts.size >= 3) cache[parts[1]] = parts[2]
        "GET" -> if (parts.size >= 2) out.appendLine(cache[parts[1]] ?: "NULL")
        "DEL" -> if (parts.size >= 2) out.appendLine(if (cache.remove(parts[1])) "1" else "0")
        "SIZE" -> out.appendLine(cache.size.toString())
    }
}
