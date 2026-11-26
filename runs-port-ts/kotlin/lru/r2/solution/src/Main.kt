import java.io.BufferedOutputStream

/** Parses a leading integer the way JavaScript's `parseInt(s, 10)` does; null if none. */
private fun parseLeadingInt(text: String): Long? {
    val s = text.trimStart()
    var i = 0
    val negative = s.startsWith('-')
    if (negative || s.startsWith('+')) i++
    val start = i
    var value = 0L
    while (i < s.length && s[i] in '0'..'9') {
        value = (value * 10 + (s[i] - '0')).coerceAtMost(Int.MAX_VALUE.toLong())
        i++
    }
    if (i == start) return null
    return if (negative) -value else value
}

fun run(input: String): String {
    val lines = input.split('\n')
    val capacity = parseLeadingInt(lines.first()) ?: return ""
    if (capacity < 1) return ""

    val cache = LruCache<String, String>(capacity.toInt())
    val out = StringBuilder()

    for (index in 1 until lines.size) {
        val line = lines[index].removeSuffix("\r")
        if (line.isEmpty()) continue

        val sp1 = line.indexOf(' ')
        val cmd = if (sp1 == -1) line else line.substring(0, sp1)
        when (cmd) {
            "SET" -> {
                val sp2 = line.indexOf(' ', sp1 + 1)
                if (sp2 != -1) cache[line.substring(sp1 + 1, sp2)] = line.substring(sp2 + 1)
            }
            "GET" -> if (sp1 != -1) out.append(cache[line.substring(sp1 + 1)] ?: "NULL").append('\n')
            "DEL" -> if (sp1 != -1) out.append(if (cache.remove(line.substring(sp1 + 1))) '1' else '0').append('\n')
            "SIZE" -> out.append(cache.size).append('\n')
            else -> Unit // Unknown commands are ignored.
        }
    }
    return out.toString()
}

fun main() {
    val input = System.`in`.readBytes().toString(Charsets.ISO_8859_1)
    BufferedOutputStream(System.out, 1 shl 16).use { it.write(run(input).toByteArray(Charsets.ISO_8859_1)) }
}
