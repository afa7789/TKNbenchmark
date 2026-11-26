package kvhttp

import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.SocketTimeoutException

const val MAX_HEADER_BYTES = 64 * 1024
const val MAX_BODY_BYTES = 1024 * 1024

class Request(
    val method: String,
    val target: String,
    val headers: List<Pair<String, String>>,
    val body: ByteArray,
) {
    /** Case-insensitive header lookup; returns the first match. */
    fun header(name: String): String? = headers.firstOrNull { it.first.equals(name, ignoreCase = true) }?.second
}

class Response(
    val status: Int,
    val contentType: String? = null,
    val body: ByteArray = EMPTY,
) {
    companion object {
        private val EMPTY = ByteArray(0)
    }
}

/** Raised while reading a request that cannot be served; carries the status to reply with. */
class HttpException(val status: Int) : Exception("HTTP $status")

private fun String.trimOws(): String = trim { it == ' ' || it == '\t' }

/** Buffered reader over a socket input stream that understands CRLF-terminated lines. */
private class RequestReader(private val input: InputStream) {
    private var buf = ByteArray(16 * 1024)
    private var start = 0
    private var end = 0

    private val available get() = end - start

    /** Reads more bytes into the buffer; returns false on EOF. */
    fun fill(): Boolean {
        if (start > 0 && start == end) {
            start = 0
            end = 0
        }
        if (end == buf.size) {
            if (start > 0) {
                buf.copyInto(buf, 0, start, end)
                end -= start
                start = 0
            } else {
                buf = buf.copyOf(buf.size * 2)
            }
        }
        val n = try {
            input.read(buf, end, buf.size - end)
        } catch (e: SocketTimeoutException) {
            throw HttpException(408)
        } catch (e: IOException) {
            throw HttpException(408)
        }
        if (n <= 0) return false
        end += n
        return true
    }

    /** Returns the next CRLF-terminated line (without terminator), decoded as Latin-1. */
    fun readLine(limit: Int): String {
        var scanFrom = start
        while (true) {
            for (i in scanFrom until end - 1) {
                if (buf[i] == '\r'.code.toByte() && buf[i + 1] == '\n'.code.toByte()) {
                    val line = String(buf, start, i - start, Charsets.ISO_8859_1)
                    start = i + 2
                    return line
                }
            }
            if (available > limit) throw HttpException(431)
            scanFrom = maxOf(start, end - 1)
            val offset = scanFrom - start
            if (!fill()) throw HttpException(400)
            scanFrom = start + offset
        }
    }

    /** Appends exactly [n] bytes to [out] starting at [offset]. */
    fun readExact(n: Int, out: ByteArray, offset: Int) {
        var copied = 0
        while (copied < n) {
            if (available == 0 && !fill()) throw HttpException(400)
            val take = minOf(available, n - copied)
            buf.copyInto(out, offset + copied, start, start + take)
            start += take
            copied += take
        }
    }

    fun hasData(): Boolean = available > 0 || fill()
}

private fun parseSize(s: String, radix: Int): Int {
    if (s.isEmpty() || s.any { Character.digit(it, radix) < 0 }) throw HttpException(400)
    val value = s.toBigInteger(radix)
    return if (value > MAX_BODY_BYTES.toBigInteger()) Int.MAX_VALUE else value.toInt()
}

private fun readChunkedBody(reader: RequestReader): ByteArray {
    var body = ByteArray(0)
    while (true) {
        val line = reader.readLine(MAX_HEADER_BYTES)
        val size = parseSize(line.substringBefore(';').trimOws(), 16)
        if (size == 0) break
        if (size > MAX_BODY_BYTES || body.size + size > MAX_BODY_BYTES) throw HttpException(413)
        val offset = body.size
        body = body.copyOf(offset + size)
        reader.readExact(size, body, offset)
        if (reader.readLine(0).isNotEmpty()) throw HttpException(400)
    }
    // Trailer section, terminated by an empty line.
    var total = 0
    while (true) {
        val line = reader.readLine(MAX_HEADER_BYTES)
        if (line.isEmpty()) break
        total += line.length
        if (total > MAX_HEADER_BYTES) throw HttpException(431)
    }
    return body
}

/**
 * Reads one request from [input]. Returns null if the peer closed the connection
 * before sending anything. Throws [HttpException] on malformed input.
 */
fun readRequest(input: InputStream): Request? {
    val reader = RequestReader(input)
    if (!reader.hasData()) return null

    var requestLine = reader.readLine(MAX_HEADER_BYTES)
    // Tolerate stray blank lines before the request line (RFC 9112 §2.2).
    while (requestLine.isEmpty()) requestLine = reader.readLine(MAX_HEADER_BYTES)
    var headerBytes = requestLine.length

    val sp1 = requestLine.indexOf(' ')
    val sp2 = if (sp1 < 0) -1 else requestLine.indexOf(' ', sp1 + 1)
    if (sp2 < 0 || sp1 == 0 || sp2 == sp1 + 1) throw HttpException(400)
    if (!requestLine.startsWith("HTTP/", sp2 + 1)) throw HttpException(400)
    val method = requestLine.substring(0, sp1)
    val target = requestLine.substring(sp1 + 1, sp2)

    val headers = mutableListOf<Pair<String, String>>()
    while (true) {
        val line = reader.readLine(MAX_HEADER_BYTES)
        if (line.isEmpty()) break
        headerBytes += line.length
        if (headerBytes > MAX_HEADER_BYTES) throw HttpException(431)
        val colon = line.indexOf(':')
        if (colon <= 0) throw HttpException(400)
        headers += line.substring(0, colon) to line.substring(colon + 1).trimOws()
    }

    val partial = Request(method, target, headers, ByteArray(0))
    val transferEncoding = partial.header("Transfer-Encoding")
    val contentLength = partial.header("Content-Length")
    val body = when {
        transferEncoding != null -> {
            if (!transferEncoding.trimOws().equals("chunked", ignoreCase = true)) throw HttpException(501)
            readChunkedBody(reader)
        }
        contentLength != null -> {
            val length = parseSize(contentLength.trimOws(), 10)
            if (length > MAX_BODY_BYTES) throw HttpException(413)
            ByteArray(length).also { reader.readExact(length, it, 0) }
        }
        else -> return partial
    }
    return Request(method, target, headers, body)
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
    else -> "Unknown"
}

/** Serialises [response] to [output], always with exact framing and `Connection: close`. */
fun writeResponse(output: OutputStream, response: Response) {
    val head = buildString {
        append("HTTP/1.1 ").append(response.status).append(' ').append(reasonPhrase(response.status)).append("\r\n")
        response.contentType?.let { append("Content-Type: ").append(it).append("\r\n") }
        // 204 must not carry a body or Content-Length framing; everything else
        // advertises its exact length.
        if (response.status != 204) append("Content-Length: ").append(response.body.size).append("\r\n")
        append("Connection: close\r\n\r\n")
    }.toByteArray(Charsets.ISO_8859_1)

    if (response.body.size < 16 * 1024) {
        output.write(head + response.body)
    } else {
        output.write(head)
        output.write(response.body)
    }
    output.flush()
}
