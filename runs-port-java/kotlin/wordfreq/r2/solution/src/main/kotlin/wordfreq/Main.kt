package wordfreq

import java.io.InputStream

private const val TOP_N = 10
private const val READ_BUFFER_SIZE = 1 shl 16

/** Prints the ten most frequent ASCII-letter words read from standard input. */
fun main() {
    val report = buildString {
        for ((word, count) in countWords(System.`in`).top(TOP_N)) {
            append(count).append(' ').append(word).append('\n')
        }
    }
    System.out.write(report.toByteArray(Charsets.ISO_8859_1))
    System.out.flush()
}

/** Tokenizes [input] into lowercase runs of ASCII letters and counts them. */
fun countWords(input: InputStream): WordCounter {
    val counter = WordCounter()
    val buffer = ByteArray(READ_BUFFER_SIZE)
    var word = ByteArray(64)
    var wordLength = 0
    while (true) {
        val read = input.read(buffer)
        if (read < 0) break
        for (i in 0 until read) {
            val lower = buffer[i].toInt() or 0x20
            if (lower in 'a'.code..'z'.code) {
                if (wordLength == word.size) word = word.copyOf(word.size * 2)
                word[wordLength++] = lower.toByte()
            } else if (wordLength > 0) {
                counter.add(word, wordLength)
                wordLength = 0
            }
        }
    }
    if (wordLength > 0) counter.add(word, wordLength)
    return counter
}
