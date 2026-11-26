package kvhttp

import java.io.ByteArrayOutputStream
import java.io.InputStream

const val MAX_VALUE_SIZE = 1024 * 1024
const val MAX_HEADER_SIZE = 64 * 1024

enum class HttpStatus(val code: Int, val phrase: String) {
    OK(200, "OK"),
    CREATED(201, "Created"),
    NO_CONTENT(204, "No Content"),
    BAD_REQUEST(400, "Bad Request"),
    NOT_FOUND(404, "Not Found"),
    METHOD_NOT_ALLOWED(405, "Method Not Allowed"),
    CONTENT_TOO_LARGE(413, "Content Too Large"),
    REQUEST_HEADER_FIELDS_TOO_LARGE(431, "Request Header Fields Too Large"),
}

/** A protocol-level failure that is answered with [status] and an empty body. */
class HttpException(val status: HttpStatus) : Exception(status.phrase)

class Request(
    val method: String,
    val path: String,
    /** Header names are lower-cased; a repeated header keeps its last value. */
    val headers: Map<String, String>,
    val body: ByteArray = EMPTY,
)

class Response(
    val status: HttpStatus,
    val body: ByteArray = EMPTY,
    val headers: Map<String, String> = emptyMap(),
) {
    fun serialize(): ByteArray {
        val all = LinkedHashMap<String, String>()
        all["Connection"] = "close"
        all.putAll(headers)
        if (body.isNotEmpty() && "Content-Type" !in all) {
            all["Content-Type"] = "application/octet-stream"
        }
        all["Content-Length"] = body.size.toString()

        val head = buildString {
            append("HTTP/1.1 ").append(status.code).append(' ').append(status.phrase).append("\r\n")
            for ((name, value) in all) append(name).append(": ").append(value).append("\r\n")
            append("\r\n")
        }
        return head.toByteArray(Charsets.ISO_8859_1) + body
    }
}

private val EMPTY = ByteArray(0)
private val CRLF = byteArrayOf('\r'.code.toByte(), '\n'.code.toByte())
private val HEAD_TERMINATOR = CRLF + CRLF

/** Incremental HTTP/1.1 request parser over a (preferably buffered) input stream. */
class RequestReader(private val input: InputStream) {

    /** Reads one request, or returns null if the client closed without sending anything. */
    fun read(): Request? {
        val head = try {
            readUntil(HEAD_TERMINATOR, MAX_HEADER_SIZE)
        } catch (e: IncompleteReadException) {
            if (e.partial.all { it.toInt().toChar().isWhitespace() }) return null
            throw HttpException(HttpStatus.BAD_REQUEST)
        } catch (_: LimitOverrunException) {
            throw HttpException(HttpStatus.REQUEST_HEADER_FIELDS_TOO_LARGE)
        }

        val lines = String(head, Charsets.ISO_8859_1).split("\r\n")
        val requestLine = lines.first().split(" ")
        if (requestLine.size != 3) throw HttpException(HttpStatus.BAD_REQUEST)
        val (method, target, _) = requestLine

        val headers = HashMap<String, String>()
        for (line in lines.drop(1)) {
            if (line.isEmpty()) continue
            val sep = line.indexOf(':')
            if (sep < 0) throw HttpException(HttpStatus.BAD_REQUEST)
            headers[line.substring(0, sep).trim().lowercase()] = line.substring(sep + 1).trim()
        }

        val path = target.substringBefore('?')
        return Request(method, path, headers, readBody(headers))
    }

    private fun readBody(headers: Map<String, String>): ByteArray {
        if ("chunked" in headers["transfer-encoding"].orEmpty().lowercase()) return readChunked()
        val rawLength = headers["content-length"] ?: return EMPTY
        if (rawLength.isEmpty() || !rawLength.all { it in '0'..'9' }) {
            throw HttpException(HttpStatus.BAD_REQUEST)
        }
        // Digits only, so a parse failure can only mean overflow: certainly too large.
        val length = rawLength.toLongOrNull() ?: Long.MAX_VALUE
        try {
            if (length > MAX_VALUE_SIZE) {
                // Drain the body so the client reliably receives the error response.
                discard(length)
                throw HttpException(HttpStatus.CONTENT_TOO_LARGE)
            }
            return readExactly(length.toInt())
        } catch (_: IncompleteReadException) {
            throw HttpException(HttpStatus.BAD_REQUEST)
        }
    }

    private fun readChunked(): ByteArray {
        val body = ByteArrayOutputStream()
        try {
            while (true) {
                val sizeLine = String(readUntil(CRLF, MAX_HEADER_SIZE), Charsets.ISO_8859_1)
                val size = parseChunkSize(sizeLine.substringBefore(';').trim())
                if (size == 0) {
                    // Consume optional trailers up to the terminating blank line.
                    do {
                        val trailer = readUntil(CRLF, MAX_HEADER_SIZE)
                    } while (!trailer.contentEquals(CRLF))
                    return body.toByteArray()
                }
                if (body.size().toLong() + size > MAX_VALUE_SIZE) {
                    throw HttpException(HttpStatus.CONTENT_TOO_LARGE)
                }
                body.write(readExactly(size))
                readExactly(CRLF.size)
            }
        } catch (_: IncompleteReadException) {
            throw HttpException(HttpStatus.BAD_REQUEST)
        } catch (_: LimitOverrunException) {
            throw HttpException(HttpStatus.BAD_REQUEST)
        }
    }

    private fun parseChunkSize(raw: String): Int {
        val digits = raw.removePrefix("0x").removePrefix("0X")
        val size = digits.toIntOrNull(16)
        if (digits.isEmpty() || size == null || size < 0) throw HttpException(HttpStatus.BAD_REQUEST)
        return size
    }

    /** Reads up to and including [separator]; fails if it does not appear within [limit] bytes. */
    private fun readUntil(separator: ByteArray, limit: Int): ByteArray {
        val buffer = ByteArrayOutputStream()
        var matched = 0
        while (true) {
            val b = input.read()
            if (b < 0) throw IncompleteReadException(buffer.toByteArray())
            buffer.write(b)
            matched = when {
                b.toByte() == separator[matched] -> matched + 1
                b.toByte() == separator[0] -> 1
                else -> 0
            }
            if (matched == separator.size) return buffer.toByteArray()
            if (buffer.size() > limit) throw LimitOverrunException()
        }
    }

    private fun readExactly(length: Int): ByteArray {
        val data = input.readNBytes(length)
        if (data.size < length) throw IncompleteReadException(data)
        return data
    }

    private fun discard(length: Long) {
        var remaining = length
        while (remaining > 0) {
            val skipped = input.skip(remaining)
            if (skipped <= 0) {
                // skip() may return 0 without EOF; read() distinguishes the two.
                if (input.read() < 0) throw IncompleteReadException(EMPTY)
                remaining--
            } else {
                remaining -= skipped
            }
        }
    }

    private class IncompleteReadException(val partial: ByteArray) : Exception() {
        override fun fillInStackTrace(): Throwable = this
    }

    private class LimitOverrunException : Exception() {
        override fun fillInStackTrace(): Throwable = this
    }
}
