package lru

import kotlin.system.exitProcess

private const val NULL_REPLY = "NULL"

/** Runs the command script in [input] and returns the output, one reply per line. */
fun run(input: String): String {
    val lines = input.split('\n')
    val capacity = parseLeadingInt(lines.first())
    if (capacity == null || capacity < 1) return ""

    val cache = LruCache<String, String>(capacity)
    val out = StringBuilder()

    for (i in 1 until lines.size) {
        val line = lines[i].removeSuffix("\r")
        if (line.isEmpty()) continue

        val command = line.substringBefore(' ')
        val rest = line.substringAfter(' ', missingDelimiterValue = "")

        when (command) {
            "SET" -> {
                val sep = rest.indexOf(' ')
                if (sep != -1) cache[rest.substring(0, sep)] = rest.substring(sep + 1)
            }
            "GET" -> out.append(cache[rest] ?: NULL_REPLY).append('\n')
            "DEL" -> out.append(if (cache.remove(rest)) '1' else '0').append('\n')
            "SIZE" -> out.append(cache.size).append('\n')
            else -> Unit // Unknown commands are ignored.
        }
    }
    return out.toString()
}

/**
 * Parses an optionally signed decimal prefix after leading whitespace, like JavaScript's
 * `parseInt(s, 10)`. Returns `null` when there are no digits or the value overflows [Int].
 */
internal fun parseLeadingInt(text: String): Int? {
    val s = text.trimStart()
    val signLength = if (s.startsWith('-') || s.startsWith('+')) 1 else 0
    val digits = s.drop(signLength).takeWhile { it in '0'..'9' }
    if (digits.isEmpty()) return null
    return (s.take(signLength) + digits).toIntOrNull()
}

fun main() {
    val input = System.`in`.readBytes().toString(Charsets.ISO_8859_1)
    val output = run(input)
    if (output.isNotEmpty()) {
        System.out.write(output.toByteArray(Charsets.ISO_8859_1))
        System.out.flush()
    }
    exitProcess(0)
}
