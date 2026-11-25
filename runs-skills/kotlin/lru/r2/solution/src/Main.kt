import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter

private const val BUFFER_SIZE = 1 shl 16

fun main() {
    val reader = BufferedReader(InputStreamReader(System.`in`, Charsets.ISO_8859_1), BUFFER_SIZE)
    val out = BufferedWriter(OutputStreamWriter(System.out, Charsets.ISO_8859_1), BUFFER_SIZE)

    val capacity = reader.readLine()?.trim()?.toIntOrNull() ?: return
    val cache = LruCache<String, String>(capacity)

    out.use {
        while (true) {
            val line = reader.readLine()?.trimEnd('\r') ?: break
            execute(line, cache, out)
        }
    }
}

private fun execute(line: String, cache: LruCache<String, String>, out: BufferedWriter) {
    val firstSpace = line.indexOf(' ')
    val command = if (firstSpace < 0) line else line.substring(0, firstSpace)
    when (command) {
        "SET" -> {
            val secondSpace = line.indexOf(' ', firstSpace + 1)
            if (secondSpace < 0) return
            cache[line.substring(firstSpace + 1, secondSpace)] = line.substring(secondSpace + 1)
        }
        "GET" -> if (firstSpace >= 0) out.writeLine(cache[line.substring(firstSpace + 1)] ?: "NULL")
        "DEL" -> if (firstSpace >= 0) out.writeLine(if (cache.remove(line.substring(firstSpace + 1))) "1" else "0")
        "SIZE" -> out.writeLine(cache.size.toString())
    }
}

private fun BufferedWriter.writeLine(text: String) {
    write(text)
    write('\n'.code)
}
