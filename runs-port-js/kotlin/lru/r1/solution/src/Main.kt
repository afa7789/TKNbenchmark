import java.io.BufferedOutputStream

/** Parses a leading run of decimal digits (after optional whitespace and sign), like JS `parseInt`. */
private fun parseLeadingInt(text: String): Int? {
    val match = Regex("""^\s*([+-]?\d+)""").find(text) ?: return null
    return match.groupValues[1].toBigInteger()
        .coerceIn(Int.MIN_VALUE.toBigInteger(), Int.MAX_VALUE.toBigInteger())
        .toInt()
}

fun run(input: String): String {
    val lines = input.split('\n')
    // A missing or malformed capacity leaves the cache effectively unbounded.
    val capacity = parseLeadingInt(lines.first())?.coerceAtLeast(1) ?: Int.MAX_VALUE
    val cache = LruCache<String?, String?>(capacity)
    val out = StringBuilder()

    for (index in 1 until lines.size) {
        val line = lines[index].removeSuffix("\r")
        if (line.isEmpty()) continue

        val parts = line.split(' ')
        val key = parts.getOrNull(1)
        when (parts[0]) {
            "SET" -> cache[key] = parts.getOrNull(2)
            "GET" -> out.append(cache[key] ?: "NULL").append('\n')
            "DEL" -> out.append(if (cache.remove(key)) '1' else '0').append('\n')
            "SIZE" -> out.append(cache.size).append('\n')
            else -> Unit // ignore unknown commands
        }
    }
    return out.toString()
}

fun main() {
    val input = System.`in`.readBytes().toString(Charsets.ISO_8859_1)
    val output = run(input)
    if (output.isNotEmpty()) {
        BufferedOutputStream(System.out, 1 shl 16).use { it.write(output.toByteArray(Charsets.UTF_8)) }
    }
}
