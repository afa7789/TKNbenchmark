package kvhttp

import java.io.EOFException
import java.io.InputStream

const val MAX_VALUE_BYTES = 1024 * 1024
const val MAX_HEADER_BYTES = 64 * 1024

private val HEAD_END = "\r\n\r\n".toByteArray()
private val CRLF = "\r\n".toByteArray()

/** Thrown when a delimiter is not found within the allowed number of bytes. */
class LimitOverrunException : Exception("delimiter not found within limit")

/**
 * Buffered reader for HTTP/1.1 requests. Throws [EOFException] when the peer
 * closes the connection before a complete request has arrived.
 */
class RequestReader(private val input: InputStream, private val limit: Int = MAX_HEADER_BYTES) {
    private var buf = ByteArray(8192)
    private var start = 0
    private var end = 0

    fun readRequest(): Request {
        val head = try {
            readUntil(HEAD_END)
        } catch (_: LimitOverrunException) {
            throw HttpException(Status.REQUEST_HEADER_FIELDS_TOO_LARGE)
        }
        val lines = String(head, 0, head.size - HEAD_END.size, Charsets.ISO_8859_1).split("\r\n")

        val parts = lines.first().split(" ")
        if (parts.size != 3 || !parts[2].startsWith("HTTP/")) throw HttpException(Status.BAD_REQUEST)
        val (method, target) = parts

        val headers = HashMap<String, String>()
        for (line in lines.drop(1)) {
            val colon = line.indexOf(':')
            if (colon <= 0) throw HttpException(Status.BAD_REQUEST)
            val name = line.substring(0, colon)
            if (name != name.trim()) throw HttpException(Status.BAD_REQUEST)
            headers[name.lowercase()] = line.substring(colon + 1).trim()
        }

        val path = target.substringBefore('?')
        val transferEncoding = headers["transfer-encoding"]
        val body = if (transferEncoding != null) {
            if (!transferEncoding.equals("chunked", ignoreCase = true)) throw HttpException(Status.NOT_IMPLEMENTED)
            readChunkedBody()
        } else {
            readFixedBody(headers["content-length"])
        }
        return Request(method, path, headers, body)
    }

    private fun readFixedBody(rawLength: String?): ByteArray {
        if (rawLength == null) return EMPTY_BODY
        if (rawLength.isEmpty() || !rawLength.all { it in '0'..'9' }) throw HttpException(Status.BAD_REQUEST)
        val length = rawLength.trimStart('0').ifEmpty { "0" }
        // Compare lengths first so that absurdly long digit strings cannot overflow.
        if (length.length > 7 || length.toInt() > MAX_VALUE_BYTES) throw HttpException(Status.CONTENT_TOO_LARGE)
        return readExactly(length.toInt())
    }

    private fun readChunkedBody(): ByteArray {
        val chunks = mutableListOf<ByteArray>()
        var total = 0
        while (true) {
            val sizeLine = String(readLine(), Charsets.ISO_8859_1).substringBefore(';').trim()
            val size = sizeLine.toIntOrNull(16)?.takeIf { it >= 0 } ?: throw HttpException(Status.BAD_REQUEST)
            if (size == 0) {
                // Discard trailers up to the terminating blank line.
                while (!readLine().contentEquals(CRLF)) Unit
                return concat(chunks, total)
            }
            total += size
            if (total > MAX_VALUE_BYTES) throw HttpException(Status.CONTENT_TOO_LARGE)
            chunks += readExactly(size)
            if (!readExactly(CRLF.size).contentEquals(CRLF)) throw HttpException(Status.BAD_REQUEST)
        }
    }

    private fun readLine(): ByteArray = try {
        readUntil(CRLF)
    } catch (_: LimitOverrunException) {
        throw HttpException(Status.BAD_REQUEST)
    }

    /** Reads up to and including [delimiter], which must start within [limit] bytes. */
    private fun readUntil(delimiter: ByteArray): ByteArray {
        var scanned = 0 // bytes after `start` already known not to begin the delimiter
        while (true) {
            val found = indexOf(delimiter, start + scanned)
            if (found >= 0) {
                if (found - start > limit) throw LimitOverrunException()
                val stop = found + delimiter.size
                return buf.copyOfRange(start, stop).also { start = stop }
            }
            if (end - start > limit) throw LimitOverrunException()
            scanned = maxOf(0, end - start - delimiter.size + 1)
            if (!fill()) throw EOFException()
        }
    }

    private fun readExactly(n: Int): ByteArray {
        val out = ByteArray(n)
        val buffered = minOf(n, end - start)
        buf.copyInto(out, 0, start, start + buffered)
        start += buffered
        var filled = buffered
        while (filled < n) {
            val read = input.read(out, filled, n - filled)
            if (read < 0) throw EOFException()
            filled += read
        }
        return out
    }

    private fun indexOf(needle: ByteArray, from: Int): Int {
        outer@ for (i in from..end - needle.size) {
            for (j in needle.indices) if (buf[i + j] != needle[j]) continue@outer
            return i
        }
        return -1
    }

    /** Compacts or grows the buffer and reads more data; returns false at end of stream. */
    private fun fill(): Boolean {
        if (start > 0) {
            buf.copyInto(buf, 0, start, end)
            end -= start
            start = 0
        }
        if (end == buf.size) buf = buf.copyOf(buf.size * 2)
        val read = input.read(buf, end, buf.size - end)
        if (read < 0) return false
        end += read
        return true
    }

    private fun concat(chunks: List<ByteArray>, total: Int): ByteArray {
        val out = ByteArray(total)
        var offset = 0
        for (chunk in chunks) {
            chunk.copyInto(out, offset)
            offset += chunk.size
        }
        return out
    }
}
