package wordfreq

import java.io.InputStream

private const val TOP_N = 10
private const val READ_BUFFER_SIZE = 1 shl 16

/** Prints the ten most frequent ASCII words read from standard input. */
fun main() {
    val counter = countWords(System.`in`)
    val out = StringBuilder()
    for ((word, count) in counter.top(TOP_N)) {
        out.append(count).append(' ').append(word).append('\n')
    }
    System.out.write(out.toString().toByteArray(Charsets.US_ASCII))
    System.out.flush()
}

/** Tokenizes the stream into maximal runs of ASCII letters, folded to lowercase. */
internal fun countWords(input: InputStream): WordCounter {
    val counter = WordCounter()
    val chunk = ByteArray(READ_BUFFER_SIZE)
    var word = ByteArray(64)
    var wordLen = 0

    while (true) {
        val n = input.read(chunk)
        if (n < 0) break
        for (i in 0 until n) {
            val lower = chunk[i].toInt() or 0x20
            if (lower in 'a'.code..'z'.code) {
                if (wordLen == word.size) word = word.copyOf(word.size * 2)
                word[wordLen++] = lower.toByte()
            } else if (wordLen > 0) {
                counter.add(word, wordLen)
                wordLen = 0
            }
        }
    }
    if (wordLen > 0) counter.add(word, wordLen)
    return counter
}
