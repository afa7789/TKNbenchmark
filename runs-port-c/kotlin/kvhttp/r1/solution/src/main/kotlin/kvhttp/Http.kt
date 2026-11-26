package kvhttp

import java.io.OutputStream

/** The parts of a request head the server cares about. */
class RequestHead(
    val method: String,
    val target: String,
    /** Declared body length, or 0 when the request carries no `Content-Length`. */
    val contentLength: ULong,
)

sealed interface ParseResult {
    class Ok(val head: RequestHead) : ParseResult
    class Error(val status: Int) : ParseResult
}

class Response(
    val status: Int,
    val body: ByteArray = EMPTY,
    val contentType: String? = null,
    val allow: String? = null,
) {
    fun writeTo(out: OutputStream) {
        val head = buildString {
            append("HTTP/1.1 ").append(status).append(' ').append(reasonPhrase(status)).append("\r\n")
            append("Content-Length: ").append(body.size).append("\r\n")
            append("Connection: close\r\n")
            contentType?.let { append("Content-Type: ").append(it).append("\r\n") }
            allow?.let { append("Allow: ").append(it).append("\r\n") }
            append("\r\n")
        }
        out.write(head.toByteArray(Charsets.ISO_8859_1))
        if (body.isNotEmpty()) out.write(body)
        out.flush()
    }

    companion object {
        private val EMPTY = ByteArray(0)

        fun empty(status: Int) = Response(status)

        fun text(status: Int, text: String) =
            Response(status, text.toByteArray(Charsets.UTF_8), contentType = "text/plain; charset=utf-8")

        fun methodNotAllowed(allow: String) = Response(405, allow = allow)
    }
}

fun reasonPhrase(status: Int): String = when (status) {
    200 -> "OK"
    201 -> "Created"
    204 -> "No Content"
    400 -> "Bad Request"
    404 -> "Not Found"
    405 -> "Method Not Allowed"
    408 -> "Request Timeout"
    413 -> "Content Too Large"
    431 -> "Request Header Fields Too Large"
    500 -> "Internal Server Error"
    501 -> "Not Implemented"
    505 -> "HTTP Version Not Supported"
    else -> "Unknown"
}

private const val CR = '\r'.code.toByte()
private const val LF = '\n'.code.toByte()
private const val SP = ' '.code.toByte()
private const val COLON = ':'.code.toByte()
private const val TCHAR_SYMBOLS = "!#$%&'*+-.^_`|~"

private fun isTchar(b: Byte): Boolean {
    val c = (b.toInt() and 0xFF).toChar()
    return c in 'A'..'Z' || c in 'a'..'z' || c in '0'..'9' || c in TCHAR_SYMBOLS
}

private fun isOws(b: Byte): Boolean = b == SP || b == '\t'.code.toByte()

private fun ByteArray.indexOf(b: Byte, from: Int, to: Int): Int {
    for (i in from until to) if (this[i] == b) return i
    return -1
}

private fun ByteArray.latin1(from: Int, to: Int) = String(this, from, to - from, Charsets.ISO_8859_1)

private fun ByteArray.regionEqualsIgnoreCase(from: Int, to: Int, name: String): Boolean =
    to - from == name.length && latin1(from, to).equals(name, ignoreCase = true)

/** A non-empty run of ASCII digits that fits in an unsigned 64-bit integer. */
private fun parseSize(s: String): ULong? =
    if (s.isNotEmpty() && s.all { it in '0'..'9' }) s.toULongOrNull() else null

/**
 * Parses the request head in `buf[0, len)`, which excludes the terminating CRLFCRLF.
 */
fun parseHead(buf: ByteArray, len: Int): ParseResult {
    val lineEnd = buf.indexOf(CR, 0, len).let { if (it < 0) len else it }

    // Request line: method SP target SP version
    val sp1 = buf.indexOf(SP, 0, lineEnd)
    if (sp1 <= 0) return ParseResult.Error(400)
    val sp2 = buf.indexOf(SP, sp1 + 1, lineEnd)
    if (sp2 < 0 || sp2 == sp1 + 1) return ParseResult.Error(400)
    for (i in 0 until sp1) if (!isTchar(buf[i])) return ParseResult.Error(400)
    val version = buf.latin1(sp2 + 1, lineEnd)
    if (version.length != 8 || !version.startsWith("HTTP/1.")) {
        return ParseResult.Error(if (version.startsWith("HTTP/")) 505 else 400)
    }
    val method = buf.latin1(0, sp1)
    val target = buf.latin1(sp1 + 1, sp2)

    // Header fields
    var contentLength: ULong? = null
    var chunked = false
    var p = lineEnd
    while (p < len) {
        if (len - p < 2 || buf[p] != CR || buf[p + 1] != LF) return ParseResult.Error(400)
        p += 2
        val eol = buf.indexOf(CR, p, len).let { if (it < 0) len else it }
        val colon = buf.indexOf(COLON, p, eol)
        if (colon <= p) return ParseResult.Error(400)
        for (i in p until colon) if (!isTchar(buf[i])) return ParseResult.Error(400)

        var valueStart = colon + 1
        var valueEnd = eol
        while (valueStart < valueEnd && isOws(buf[valueStart])) valueStart++
        while (valueEnd > valueStart && isOws(buf[valueEnd - 1])) valueEnd--

        when {
            buf.regionEqualsIgnoreCase(p, colon, "Content-Length") -> {
                val cl = parseSize(buf.latin1(valueStart, valueEnd)) ?: return ParseResult.Error(400)
                if (contentLength != null && contentLength != cl) return ParseResult.Error(400)
                contentLength = cl
            }
            buf.regionEqualsIgnoreCase(p, colon, "Transfer-Encoding") -> chunked = true
        }
        p = eol
    }

    if (chunked) return ParseResult.Error(if (contentLength != null) 400 else 501)
    return ParseResult.Ok(RequestHead(method, target, contentLength ?: 0u))
}
