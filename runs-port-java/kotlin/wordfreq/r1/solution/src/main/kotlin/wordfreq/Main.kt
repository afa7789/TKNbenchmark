package wordfreq

import java.io.InputStream

private const val TOP_N = 10
private const val BUFFER_SIZE = 1 shl 16

/** Reads standard input and prints the ten most frequent ASCII words. */
fun main() {
    val counter = countWords(System.`in`)
    val output = buildString {
        for ((word, count) in counter.top(TOP_N)) {
            append(count).append(' ').append(word).append('\n')
        }
    }
    System.out.write(output.toByteArray(Charsets.US_ASCII))
    System.out.flush()
}

/** Splits [input] into maximal runs of ASCII letters, folded to lowercase, and counts them. */
fun countWords(input: InputStream): WordCounter {
    val counter = WordCounter()
    val buf = ByteArray(BUFFER_SIZE)
    var word = ByteArray(64)
    var wordLen = 0
    var hash = 0
    while (true) {
        val n = input.read(buf)
        if (n < 0) break
        for (i in 0 until n) {
            // Setting bit 0x20 maps 'A'..'Z' onto 'a'..'z' and no other byte into that range.
            val lower = buf[i].toInt() or 0x20
            if (lower in 'a'.code..'z'.code) {
                if (wordLen == word.size) word = word.copyOf(word.size * 2)
                word[wordLen++] = lower.toByte()
                hash = hash * 31 + lower
            } else if (wordLen > 0) {
                counter.add(word, wordLen, hash)
                wordLen = 0
                hash = 0
            }
        }
    }
    if (wordLen > 0) counter.add(word, wordLen, hash)
    return counter
}
