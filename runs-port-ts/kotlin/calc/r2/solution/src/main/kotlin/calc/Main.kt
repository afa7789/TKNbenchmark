package calc

fun main() {
    val input = System.`in`.readBytes().toString(Charsets.ISO_8859_1)
    val lines = input.split('\n').let { if (it.last().isEmpty()) it.dropLast(1) else it }

    val out = StringBuilder()
    for (line in lines) {
        evaluateLine(line)?.let { out.append(it).append('\n') }
    }
    System.out.write(out.toString().toByteArray(Charsets.ISO_8859_1))
    System.out.flush()
}
