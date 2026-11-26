package kvhttp

import java.io.BufferedInputStream
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.InputStream
import java.io.OutputStream
import java.io.SequenceInputStream

/** Maximum size of the request line plus headers. */
const val HEAD_MAX_BYTES = 16 * 1024

private const val CHUNK_LINE_MAX = 256

class HttpRequest(val method: String, val target: String, val body: ByteArray)

class HttpResponse(
    val status: Int,
    val contentType: String? = null,
    val body: ByteArray = EMPTY_BODY,
) {
    private companion object {
        val EMPTY_BODY = ByteArray(0)
    }
}

/**
 * A malformed or unacceptable request that should be answered with [status].
 * Peer disconnects and timeouts surface as [java.io.IOException] instead.
 */
class HttpException(val status: Int) : Exception("HTTP $status", null, false, false)

private class BodyFraming(
    var contentLength: Long? = null,
    var chunked: Boolean = false,
    var expectContinue: Boolean = false,
)

/**
 * Reads a single HTTP/1.1 request from [input], accepting bodies up to [maxBody] bytes.
 * [output] is used only to send `100 Continue` when the client asks for it.
 *
 * @throws HttpException when the request must be rejected with a status code.
 * @throws java.io.IOException when the peer went away or timed out.
 */
fun readRequest(input: InputStream, output: OutputStream, maxBody: Int): HttpRequest {
    val head = ByteArray(HEAD_MAX_BYTES)
    var filled = 0
    var headEnd = 0
    while (headEnd == 0) {
        if (filled == head.size) throw HttpException(431)
        val n = input.read(head, filled, head.size - filled)
        if (n < 0) throw EOFException("connection closed before request head")
        // The terminator may straddle reads, so rescan the last two old bytes.
        headEnd = findHeadEnd(head, maxOf(0, filled - 2), filled + n)
        filled += n
    }

    val headText = String(head, 0, headEnd, Charsets.ISO_8859_1)
    val (method, target, framing) = parseHead(headText)

    val length = framing.contentLength
    if (length != null && length > maxBody) throw HttpException(413)
    if (framing.expectContinue && (framing.chunked || (length ?: 0) > 0)) {
        output.write("HTTP/1.1 100 Continue\r\n\r\n".toByteArray(Charsets.US_ASCII))
        output.flush()
    }

    // Bytes that arrived together with the head belong to the body.
    val bodyInput = BufferedInputStream(
        SequenceInputStream(ByteArrayInputStream(head, headEnd, filled - headEnd), input),
    )
    val body = when {
        framing.chunked -> readChunked(bodyInput, maxBody)
        length != null && length > 0 -> bodyInput.readExactly(length.toInt())
        else -> ByteArray(0)
    }
    return HttpRequest(method, target, body)
}

/** Writes a complete response with `Content-Length` and `Connection: close`. */
fun writeResponse(output: OutputStream, response: HttpResponse) {
    val head = buildString {
        append("HTTP/1.1 ").append(response.status).append(' ').append(reasonPhrase(response.status)).append("\r\n")
        response.contentType?.let { append("Content-Type: ").append(it).append("\r\n") }
        append("Content-Length: ").append(response.body.size).append("\r\n")
        append("Connection: close\r\n\r\n")
    }
    output.write(head.toByteArray(Charsets.US_ASCII))
    output.write(response.body)
    output.flush()
}

/** Returns the offset just past the blank line ending the head, or 0 if not found yet. */
private fun findHeadEnd(buf: ByteArray, from: Int, len: Int): Int {
    for (i in from until len - 1) {
        if (buf[i] != LF) continue
        if (buf[i + 1] == LF) return i + 2
        if (i + 2 < len && buf[i + 1] == CR && buf[i + 2] == LF) return i + 3
    }
    return 0
}

private fun parseHead(head: String): Triple<String, String, BodyFraming> {
    val lines = head.split('\n').map { it.removeSuffix("\r") }
    val requestLine = lines.first()

    // Request line: method SP target SP HTTP/1.x
    val sp1 = requestLine.indexOf(' ')
    if (sp1 < 0) throw HttpException(400)
    val sp2 = requestLine.indexOf(' ', sp1 + 1)
    if (sp2 < 0) throw HttpException(400)
    val method = requestLine.substring(0, sp1)
    val target = requestLine.substring(sp1 + 1, sp2)
    val version = requestLine.substring(sp2 + 1)

    if (method.isEmpty() || target.isEmpty()) throw HttpException(400)
    if (!method.all(::isTokenChar)) throw HttpException(400)
    if (!HTTP_1X.matches(version)) throw HttpException(if (version.startsWith("HTTP/")) 505 else 400)

    val framing = BodyFraming()
    for (line in lines.drop(1)) {
        if (line.isEmpty()) break
        val colon = line.indexOf(':')
        if (colon <= 0) throw HttpException(400)
        val name = line.substring(0, colon)
        if (!name.all(::isTokenChar)) throw HttpException(400)
        val value = line.substring(colon + 1).trim { it == ' ' || it == '\t' }

        when {
            name.equals("Content-Length", ignoreCase = true) -> {
                val n = parseContentLength(value) ?: throw HttpException(400)
                if (framing.contentLength.let { it != null && it != n }) throw HttpException(400)
                framing.contentLength = n
            }
            name.equals("Transfer-Encoding", ignoreCase = true) -> {
                if (!value.equals("chunked", ignoreCase = true)) throw HttpException(501)
                framing.chunked = true
            }
            name.equals("Expect", ignoreCase = true) -> {
                if (!value.equals("100-continue", ignoreCase = true)) throw HttpException(417)
                framing.expectContinue = true
            }
        }
    }
    if (framing.chunked && framing.contentLength != null) throw HttpException(400)
    return Triple(method, target, framing)
}

/**
 * Parses a non-empty run of decimal digits. Returns null on any other character or on
 * values too large to matter; anything above [Long.MAX_VALUE] is clamped there, which
 * still exceeds every body limit.
 */
private fun parseContentLength(s: String): Long? {
    if (s.isEmpty() || !s.all { it in '0'..'9' }) return null
    var v = 0UL
    for (c in s) {
        if (v > (ULong.MAX_VALUE - 9UL) / 10UL) return null
        v = v * 10UL + (c - '0').toULong()
    }
    return if (v > Long.MAX_VALUE.toULong()) Long.MAX_VALUE else v.toLong()
}

private fun readChunked(input: InputStream, maxBody: Int): ByteArray {
    val body = ByteArrayOutputStream()
    while (true) {
        val line = input.readLine(CHUNK_LINE_MAX) ?: throw HttpException(400)
        val hex = line.substringBefore(';').trim { it == ' ' || it == '\t' }
        if (hex.isEmpty()) throw HttpException(400)
        var size = 0L
        for (c in hex) {
            val digit = c.digitToIntOrNull(16) ?: throw HttpException(400)
            if (size > (Long.MAX_VALUE shr 4)) throw HttpException(413)
            size = (size shl 4) or digit.toLong()
        }
        if (size == 0L) break
        if (size > maxBody - body.size()) throw HttpException(413)

        body.write(input.readExactly(size.toInt()))
        if (input.readLine(CHUNK_LINE_MAX) != "") throw HttpException(400)
    }
    // Trailer section: skip until the blank line.
    while (input.readLine(CHUNK_LINE_MAX) != "") Unit
    return body.toByteArray()
}

private fun InputStream.readExactly(n: Int): ByteArray {
    val bytes = readNBytes(n)
    if (bytes.size != n) throw EOFException("connection closed mid-body")
    return bytes
}

/**
 * Reads a line terminated by LF, stripping a trailing CR. Returns null if the line has
 * [limit] or more characters (the bytes read so far are consumed).
 */
private fun InputStream.readLine(limit: Int): String? {
    val sb = StringBuilder()
    while (true) {
        val c = read()
        if (c < 0) throw EOFException("connection closed mid-line")
        if (c == LF.toInt()) break
        if (sb.length + 1 >= limit) return null
        sb.append(c.toChar())
    }
    if (sb.endsWith('\r')) sb.setLength(sb.length - 1)
    return sb.toString()
}

private const val CR = '\r'.code.toByte()
private const val LF = '\n'.code.toByte()

private val HTTP_1X = Regex("HTTP/1\\.[0-9]")

private const val TOKEN_SYMBOLS = "!#$%&'*+-.^_`|~"

private fun isTokenChar(c: Char): Boolean =
    c in 'A'..'Z' || c in 'a'..'z' || c in '0'..'9' || c in TOKEN_SYMBOLS

private fun reasonPhrase(status: Int): String = when (status) {
    100 -> "Continue"
    200 -> "OK"
    201 -> "Created"
    204 -> "No Content"
    400 -> "Bad Request"
    404 -> "Not Found"
    405 -> "Method Not Allowed"
    413 -> "Content Too Large"
    417 -> "Expectation Failed"
    431 -> "Request Header Fields Too Large"
    500 -> "Internal Server Error"
    501 -> "Not Implemented"
    505 -> "HTTP Version Not Supported"
    else -> "Unknown"
}
