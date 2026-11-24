import java.io.InputStream
import java.io.PrintStream

private const val TOP_N = 10
private const val BUFFER_SIZE = 1 shl 16

/** Mutable counter boxed once per distinct word to avoid re-boxing on every increment. */
private class Counter(var value: Int = 0)

/**
 * Counts maximal runs of ASCII letters in [input], folded to lowercase.
 * All other bytes act as separators.
 */
fun countWords(input: InputStream): Map<String, Int> {
    val counts = HashMap<String, Counter>()
    val buffer = ByteArray(BUFFER_SIZE)
    var word = ByteArray(64)
    var length = 0

    fun flush() {
        if (length > 0) {
            val key = String(word, 0, length, Charsets.ISO_8859_1)
            counts.getOrPut(key) { Counter() }.value++
            length = 0
        }
    }

    while (true) {
        val read = input.read(buffer)
        if (read < 0) break
        for (i in 0 until read) {
            val b = buffer[i].toInt()
            val lower = b or 0x20
            if (lower in 'a'.code..'z'.code) {
                if (length == word.size) word = word.copyOf(word.size * 2)
                word[length++] = lower.toByte()
            } else {
                flush()
            }
        }
    }
    flush()

    return counts.mapValues { it.value.value }
}

/** Returns the [n] most frequent entries: count descending, then word ascending. */
fun topWords(counts: Map<String, Int>, n: Int = TOP_N): List<Pair<String, Int>> =
    counts.entries
        .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
        .take(n)
        .map { it.key to it.value }

fun main() {
    val top = topWords(countWords(System.`in`))
    val out = PrintStream(System.out.buffered(), false, Charsets.ISO_8859_1)
    for ((word, count) in top) out.print("$count $word\n")
    out.flush()
}
