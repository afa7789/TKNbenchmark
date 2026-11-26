package kvhttp

import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.InputStream

const val MAX_VALUE_BYTES = 1024 * 1024
const val MAX_HEADER_BYTES = 64 * 1024

enum class Status(val code: Int, val phrase: String) {
    OK(200, "OK"),
    CREATED(201, "Created"),
    NO_CONTENT(204, "No Content"),
    BAD_REQUEST(400, "Bad Request"),
    NOT_FOUND(404, "Not Found"),
    METHOD_NOT_ALLOWED(405, "Method Not Allowed"),
    CONTENT_TOO_LARGE(413, "Content Too Large"),
    REQUEST_HEADER_FIELDS_TOO_LARGE(431, "Request Header Fields Too Large"),
    INTERNAL_SERVER_ERROR(500, "Internal Server Error"),
}

/** Raised while parsing a request; the server answers with [status] and closes. */
class HttpException(val status: Status) : Exception(status.phrase)

class Request(
    val method: String,
    val path: String,
    /** Header names are lower-cased. */
    val headers: Map<String, String>,
    val body: ByteArray,
)

class Response(
    val status: Status,
    val body: ByteArray = ByteArray(0),
    val headers: Map<String, String> = emptyMap(),
) {
    fun encode(): ByteArray {
        val head = buildString {
            append("HTTP/1.1 ").append(status.code).append(' ').append(status.phrase).append("\r\n")
            if (status != Status.NO_CONTENT) append("Content-Length: ").append(body.size).append("\r\n")
            append("Connection: close\r\n")
            for ((name, value) in headers) append(name).append(": ").append(value).append("\r\n")
            append("\r\n")
        }
        return head.toByteArray(Charsets.ISO_8859_1) + body
    }
}

/** Reads one HTTP/1.1 request from [input]; throws [EOFException] if the peer hangs up early. */
fun readRequest(input: InputStream): Request {
    val head = readHead(input).toString(Charsets.ISO_8859_1)
    val lines = head.split("\r\n")
    val parts = lines.first().split(" ")
    if (parts.size != 3 || !parts[2].startsWith("HTTP/")) throw HttpException(Status.BAD_REQUEST)
    val (method, target, _) = parts

    val headers = HashMap<String, String>()
    for (line in lines.drop(1)) {
        val colon = line.indexOf(':')
        if (colon <= 0) throw HttpException(Status.BAD_REQUEST)
        val name = line.substring(0, colon)
        if (name != name.trim()) throw HttpException(Status.BAD_REQUEST)
        headers[name.lowercase()] = line.substring(colon + 1).trim()
    }

    val body = if ("chunked" in headers["transfer-encoding"].orEmpty().lowercase()) {
        readChunked(input)
    } else {
        val rawLength = headers["content-length"] ?: "0"
        if (rawLength.isEmpty() || !rawLength.all { it in '0'..'9' }) throw HttpException(Status.BAD_REQUEST)
        val length = rawLength.toBigInteger()
        if (length > MAX_VALUE_BYTES.toBigInteger()) throw HttpException(Status.CONTENT_TOO_LARGE)
        input.readExactly(length.toInt())
    }

    return Request(method, target.substringBefore('?'), headers, body)
}

/** Reads up to and excluding the blank line that ends the header block. */
private fun readHead(input: InputStream): ByteArray {
    val buf = ByteArrayOutputStream(512)
    var matched = 0 // how many bytes of "\r\n\r\n" have been seen in a row
    while (true) {
        val b = input.read()
        if (b < 0) throw EOFException("connection closed before end of headers")
        buf.write(b)
        matched = when {
            b == '\r'.code -> if (matched == 2) 3 else 1
            b == '\n'.code && (matched == 1 || matched == 3) -> matched + 1
            else -> 0
        }
        if (matched == 4) break
        if (buf.size() > MAX_HEADER_BYTES) throw HttpException(Status.REQUEST_HEADER_FIELDS_TOO_LARGE)
    }
    val bytes = buf.toByteArray()
    return bytes.copyOf(bytes.size - 4)
}

private fun readChunked(input: InputStream): ByteArray {
    val out = ByteArrayOutputStream()
    while (true) {
        val sizeField = input.readLine().substringBefore(';').trim()
        val size = sizeField.toIntOrNull(16)?.takeIf { it >= 0 } ?: throw HttpException(Status.BAD_REQUEST)
        if (size == 0) {
            // Skip trailers up to the terminating blank line.
            do { val trailer = input.readLine() } while (trailer.isNotEmpty())
            return out.toByteArray()
        }
        if (out.size().toLong() + size > MAX_VALUE_BYTES) throw HttpException(Status.CONTENT_TOO_LARGE)
        out.write(input.readExactly(size))
        val crlf = input.readExactly(2)
        if (crlf[0] != '\r'.code.toByte() || crlf[1] != '\n'.code.toByte()) throw HttpException(Status.BAD_REQUEST)
    }
}

/** Reads a CRLF-terminated line (without the CRLF), bounded by [MAX_HEADER_BYTES]. */
private fun InputStream.readLine(): String {
    val buf = ByteArrayOutputStream(64)
    var prev = -1
    while (true) {
        val b = read()
        if (b < 0) throw EOFException("connection closed mid-line")
        if (prev == '\r'.code && b == '\n'.code) break
        if (prev >= 0) buf.write(prev)
        prev = b
        if (buf.size() > MAX_HEADER_BYTES) throw HttpException(Status.REQUEST_HEADER_FIELDS_TOO_LARGE)
    }
    return buf.toString(Charsets.ISO_8859_1)
}

private fun InputStream.readExactly(n: Int): ByteArray {
    val bytes = readNBytes(n)
    if (bytes.size != n) throw EOFException("expected $n bytes, got ${bytes.size}")
    return bytes
}
