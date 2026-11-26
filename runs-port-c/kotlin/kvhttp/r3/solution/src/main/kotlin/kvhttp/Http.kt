// Minimal HTTP/1.1 request-head parsing and response formatting.
package kvhttp

data class RequestHead(
    val method: String,
    val target: String,
    val contentLength: ULong,
    val expectContinue: Boolean,
)

sealed interface HeadParse {
    data class Ok(val head: RequestHead) : HeadParse

    /** The head is invalid; [status] (400, 501 or 505) says why. */
    data class Invalid(val status: Int) : HeadParse
}

class Response(
    val status: Int,
    val body: ByteArray = EMPTY_BODY,
    val contentType: String? = null,
) {
    /** Serialized status line and headers. A 204 carries neither body nor Content-Length. */
    fun encodeHead(): ByteArray {
        val head = if (status == 204) {
            "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n"
        } else buildString {
            append("HTTP/1.1 ").append(status).append(' ').append(Http.reason(status)).append("\r\n")
            contentType?.let { append("Content-Type: ").append(it).append("\r\n") }
            append("Content-Length: ").append(body.size).append("\r\n")
            append("Connection: close\r\n\r\n")
        }
        return head.toByteArray(Charsets.ISO_8859_1)
    }

    /** Body bytes to send after the head. */
    fun encodedBody(): ByteArray = if (status == 204) EMPTY_BODY else body

    companion object {
        val EMPTY_BODY = ByteArray(0)
    }
}

object Http {
    val CONTINUE_LINE: ByteArray = "HTTP/1.1 100 Continue\r\n\r\n".toByteArray(Charsets.ISO_8859_1)

    private const val TOKEN_SYMBOLS = "!#$%&'*+-.^_`|~"
    private val MAX_LENGTH_BEFORE_DIGIT = (ULong.MAX_VALUE - 9u) / 10u

    /**
     * Returns the length of the request head (through the blank line) if the first [len] bytes of
     * [buf] contain a complete head, otherwise 0. Accepts both CRLF CRLF and bare LF LF terminators.
     * Scanning starts at [from], which lets callers skip bytes already known to hold no terminator.
     */
    fun headLength(buf: ByteArray, len: Int, from: Int = 0): Int {
        for (i in from until len - 1) {
            if (buf[i] != LF) continue
            if (buf[i + 1] == LF) return i + 2
            if (buf[i + 1] == CR && i + 2 < len && buf[i + 2] == LF) return i + 3
        }
        return 0
    }

    /** Parses a complete request head occupying the first [headLen] bytes of [buf]. */
    fun parseHead(buf: ByteArray, headLen: Int): HeadParse {
        val text = String(buf, 0, headLen, Charsets.ISO_8859_1)
        val end = text.length

        // Tolerate leading empty lines (RFC 9112 section 2.2).
        var p = 0
        while (p < end && (text[p] == '\r' || text[p] == '\n')) p++

        var eol = text.indexOf('\n', p)
        if (eol < 0) return HeadParse.Invalid(400)
        val (method, target) = when (val line = parseRequestLine(text.substring(p, eol))) {
            is RequestLine.Ok -> line.method to line.target
            is RequestLine.Invalid -> return HeadParse.Invalid(line.status)
        }

        var contentLength: ULong? = null
        var expectContinue = false
        p = eol + 1
        while (p < end) {
            eol = text.indexOf('\n', p)
            if (eol < 0) return HeadParse.Invalid(400)
            val raw = text.substring(p, eol)
            p = eol + 1
            val line = raw.trimHttp()
            if (line.isEmpty()) break // end of head
            if (raw[0] == ' ' || raw[0] == '\t') return HeadParse.Invalid(400) // obsolete line folding

            val colon = line.indexOf(':')
            if (colon <= 0) return HeadParse.Invalid(400)
            val name = line.substring(0, colon)
            if (!name.all(::isTokenChar)) return HeadParse.Invalid(400)
            val value = line.substring(colon + 1).trimHttp()

            when {
                name.equals("Content-Length", ignoreCase = true) -> {
                    val n = parseLength(value) ?: return HeadParse.Invalid(400)
                    if (contentLength != null && contentLength != n) return HeadParse.Invalid(400)
                    contentLength = n
                }
                name.equals("Transfer-Encoding", ignoreCase = true) ->
                    if (!value.equals("identity", ignoreCase = true)) return HeadParse.Invalid(501)
                name.equals("Expect", ignoreCase = true) ->
                    if (value.equals("100-continue", ignoreCase = true)) expectContinue = true
            }
        }
        return HeadParse.Ok(RequestHead(method, target, contentLength ?: 0u, expectContinue))
    }

    fun reason(status: Int): String = when (status) {
        100 -> "Continue"
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
        503 -> "Service Unavailable"
        505 -> "HTTP Version Not Supported"
        else -> "Unknown"
    }

    private sealed interface RequestLine {
        data class Ok(val method: String, val target: String) : RequestLine
        data class Invalid(val status: Int) : RequestLine
    }

    private fun parseRequestLine(line: String): RequestLine {
        val sp1 = line.indexOf(' ')
        if (sp1 < 0) return RequestLine.Invalid(400)
        val sp2 = line.indexOf(' ', sp1 + 1)
        if (sp2 < 0) return RequestLine.Invalid(400)

        val method = line.substring(0, sp1)
        val target = line.substring(sp1 + 1, sp2)
        val version = line.substring(sp2 + 1).trimHttp()

        if (method.isEmpty() || target.isEmpty()) return RequestLine.Invalid(400)
        if (!method.all(::isTokenChar)) return RequestLine.Invalid(400)
        val wellFormed = version.length == 8 && version.startsWith("HTTP/") &&
            version[5].isAsciiDigit() && version[6] == '.' && version[7].isAsciiDigit()
        if (!wellFormed) return RequestLine.Invalid(400)
        if (version[5] != '1') return RequestLine.Invalid(505)
        return RequestLine.Ok(method, target)
    }

    /** Parses a Content-Length value: one or more digits, no sign, no overflow. */
    private fun parseLength(value: String): ULong? {
        if (value.isEmpty()) return null
        var n = 0uL
        for (c in value) {
            if (!c.isAsciiDigit() || n > MAX_LENGTH_BEFORE_DIGIT) return null
            n = n * 10u + (c - '0').toULong()
        }
        return n
    }

    private fun isTokenChar(c: Char): Boolean =
        c.isAsciiDigit() || c in 'a'..'z' || c in 'A'..'Z' || c in TOKEN_SYMBOLS

    private fun Char.isAsciiDigit() = this in '0'..'9'

    /** Strips leading spaces/tabs and trailing spaces/tabs/CRs. */
    private fun String.trimHttp(): String =
        trimStart(' ', '\t').trimEnd(' ', '\t', '\r')

    private const val CR = '\r'.code.toByte()
    private const val LF = '\n'.code.toByte()
}
