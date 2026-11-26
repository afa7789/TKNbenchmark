package kvhttp

import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

class Request(val method: String, val target: String, val body: ByteArray)

class Response(
    val status: Int,
    val body: ByteArray = EMPTY,
    val headers: List<Pair<String, String>> = emptyList(),
) {
    companion object {
        private val EMPTY = ByteArray(0)

        fun empty(status: Int, vararg headers: Pair<String, String>) = Response(status, headers = headers.toList())

        fun text(status: Int, body: String, contentType: String = "text/plain; charset=utf-8") =
            Response(status, body.toByteArray(Charsets.UTF_8), listOf("Content-Type" to contentType))
    }
}

/** Limits applied while reading a request. */
data class Limits(
    val maxHeaderBytes: Int = 64 * 1024,
    val maxBodyBytes: Int = 1024 * 1024,
)

/** Outcome of reading one request off a connection. */
sealed interface ReadResult {
    data class Ok(val request: Request) : ReadResult

    /** The request was malformed; send [response] instead of routing. */
    data class Error(val response: Response) : ReadResult

    /** The peer went away or timed out; nothing to answer. */
    data object Closed : ReadResult
}

fun reasonPhrase(status: Int): String = when (status) {
    200 -> "OK"
    201 -> "Created"
    204 -> "No Content"
    400 -> "Bad Request"
    404 -> "Not Found"
    405 -> "Method Not Allowed"
    408 -> "Request Timeout"
    411 -> "Length Required"
    413 -> "Content Too Large"
    431 -> "Request Header Fields Too Large"
    500 -> "Internal Server Error"
    501 -> "Not Implemented"
    505 -> "HTTP Version Not Supported"
    else -> "Unknown"
}

private const val CHUNK_SIZE = 16 * 1024
private val HEADER_END = byteArrayOf('\r'.code.toByte(), '\n'.code.toByte(), '\r'.code.toByte(), '\n'.code.toByte())

private fun fail(status: Int) = ReadResult.Error(Response.empty(status))

/** Index of [HEADER_END] in buf[0, size) starting at [from], or -1. */
private fun findHeaderEnd(buf: ByteArray, size: Int, from: Int): Int {
    for (i in from..size - HEADER_END.size) {
        if (buf[i] == HEADER_END[0] && buf[i + 1] == HEADER_END[1] &&
            buf[i + 2] == HEADER_END[2] && buf[i + 3] == HEADER_END[3]
        ) return i
    }
    return -1
}

/** Reads and throws away [remaining] bytes so the peer sees a clean close rather than a reset. */
private fun InputStream.discard(remaining: Long) {
    var left = remaining
    val scratch = ByteArray(CHUNK_SIZE)
    while (left > 0) {
        val n = read(scratch, 0, minOf(scratch.size.toLong(), left).toInt())
        if (n <= 0) return
        left -= n
    }
}

/** Reads one request from [input]. Socket timeouts and resets are reported as [ReadResult.Closed]. */
fun readRequest(input: InputStream, limits: Limits): ReadResult = try {
    parseRequest(input, limits)
} catch (_: IOException) {
    ReadResult.Closed
}

private fun parseRequest(input: InputStream, limits: Limits): ReadResult {
    var buf = ByteArray(CHUNK_SIZE)
    var size = 0
    var headerEnd = -1

    while (headerEnd < 0) {
        if (size > limits.maxHeaderBytes) return fail(431)
        if (buf.size - size < CHUNK_SIZE) buf = buf.copyOf(buf.size * 2)
        val n = input.read(buf, size, CHUNK_SIZE)
        if (n <= 0) return ReadResult.Closed
        val searchFrom = maxOf(0, size - 3)
        size += n
        headerEnd = findHeaderEnd(buf, size, searchFrom)
    }
    if (headerEnd > limits.maxHeaderBytes) return fail(431)

    val head = String(buf, 0, headerEnd, Charsets.ISO_8859_1)
    val lines = head.split("\r\n")
    val requestLine = lines.first()

    // request-line = method SP request-target SP HTTP-version
    val sp1 = requestLine.indexOf(' ')
    val sp2 = if (sp1 < 0) -1 else requestLine.indexOf(' ', sp1 + 1)
    if (sp2 < 0 || sp1 == 0 || sp2 == sp1 + 1) return fail(400)
    val version = requestLine.substring(sp2 + 1)
    if (!version.startsWith("HTTP/1.")) return fail(if (version.startsWith("HTTP/")) 505 else 400)

    val method = requestLine.substring(0, sp1)
    val target = requestLine.substring(sp1 + 1, sp2)

    var contentLength: Long? = null
    for (line in lines.drop(1)) {
        val colon = line.indexOf(':')
        if (colon <= 0) return fail(400)
        val name = line.substring(0, colon)
        val value = line.substring(colon + 1).trim(' ', '\t')

        when {
            name.equals("Content-Length", ignoreCase = true) -> {
                if (value.isEmpty() || !value.all { it in '0'..'9' }) return fail(400)
                val len = value.toLongOrNull() ?: return fail(400)
                if (contentLength != null && contentLength != len) return fail(400)
                contentLength = len
            }
            name.equals("Transfer-Encoding", ignoreCase = true) -> return fail(501)
        }
    }

    val length = contentLength ?: 0L
    val bodyStart = headerEnd + HEADER_END.size
    val already = size - bodyStart
    if (length > limits.maxBodyBytes) {
        if (already < length) input.discard(length - already)
        return fail(413)
    }

    val body = ByteArray(length.toInt())
    var filled = minOf(already, body.size)
    System.arraycopy(buf, bodyStart, body, 0, filled)
    while (filled < body.size) {
        val n = input.read(body, filled, body.size - filled)
        if (n <= 0) return ReadResult.Closed // truncated body: peer is gone
        filled += n
    }
    return ReadResult.Ok(Request(method, target, body))
}

/** Writes the full response. Throws [IOException] if the peer went away. */
fun writeResponse(output: OutputStream, response: Response) {
    val head = buildString {
        append("HTTP/1.1 ").append(response.status).append(' ').append(reasonPhrase(response.status)).append("\r\n")
        for ((name, value) in response.headers) append(name).append(": ").append(value).append("\r\n")
        if (response.status != 204) append("Content-Length: ").append(response.body.size).append("\r\n")
        append("Connection: close\r\n\r\n")
    }
    output.write(head.toByteArray(Charsets.ISO_8859_1))
    if (response.body.isNotEmpty()) output.write(response.body)
    output.flush()
}
