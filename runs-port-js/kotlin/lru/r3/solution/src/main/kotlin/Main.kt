import java.io.BufferedOutputStream
import java.io.PrintStream
import kotlin.system.exitProcess

private fun parseCapacity(line: String?): Int =
    line?.trim()?.takeWhile { it.isDigit() }?.toIntOrNull()?.takeIf { it >= 1 }
        ?: run {
            System.err.println("invalid capacity: ${line ?: "<missing>"}")
            exitProcess(1)
        }

fun main() {
    val input = System.`in`.readBytes().toString(Charsets.ISO_8859_1)
    val lines = input.lineSequence().iterator()
    val cache = LruCache<String, String>(parseCapacity(if (lines.hasNext()) lines.next() else null))
    val out = PrintStream(BufferedOutputStream(System.out, 1 shl 16), false, Charsets.ISO_8859_1)

    for (rawLine in lines) {
        val line = rawLine.removeSuffix("\r")
        if (line.isEmpty()) continue
        val sp1 = line.indexOf(' ')
        val command = if (sp1 < 0) line else line.substring(0, sp1)
        val args = line.substring(sp1 + 1)
        when (command) {
            "SET" -> {
                val sp2 = args.indexOf(' ')
                if (sp2 >= 0) cache[args.substring(0, sp2)] = args.substring(sp2 + 1)
            }
            "GET" -> out.println(cache[args] ?: "NULL")
            "DEL" -> out.println(if (cache.remove(args)) "1" else "0")
            "SIZE" -> out.println(cache.size)
            else -> Unit // ignore unknown commands
        }
    }
    out.flush()
}
