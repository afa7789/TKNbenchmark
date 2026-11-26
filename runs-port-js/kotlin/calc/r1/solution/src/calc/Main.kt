package calc

import java.io.BufferedOutputStream

fun main() {
    // Latin-1 maps every byte to one char, so arbitrary input bytes never fail to decode.
    val input = System.`in`.readBytes().toString(Charsets.ISO_8859_1)
    val lines = input.split('\n').let { if (it.last().isEmpty()) it.dropLast(1) else it }

    val out = StringBuilder()
    for (line in lines) {
        processLine(line)?.let { out.append(it).append('\n') }
    }

    BufferedOutputStream(System.out).use { it.write(out.toString().toByteArray(Charsets.ISO_8859_1)) }
}
