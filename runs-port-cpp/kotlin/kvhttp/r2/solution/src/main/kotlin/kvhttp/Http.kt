package kvhttp

import java.nio.charset.StandardCharsets

class Request(
    val method: String,
    val target: String,
    val headers: List<Pair<String, String>>,
    val body: ByteArray = ByteArray(0),
) {
    /** Case-insensitive header lookup; returns the first match. */
    fun header(name: String): String? =
        headers.firstOrNull { (key, _) -> key.equals(name, ignoreCase = true) }?.second

    fun withBody(body: ByteArray) = Request(method, target, headers, body)
}

class Response(
    val status: Int,
    val headers: List<Pair<String, String>> = emptyList(),
    val body: ByteArray = ByteArray(0),
) {
    /**
     * Serializes status line and headers, including Content-Length and
     * Connection: close. The body is not included.
     */
    fun serializeHead(): ByteArray = buildString {
        append("HTTP/1.1 ").append(status).append(' ').append(reasonPhrase(status)).append(CRLF)
        for ((key, value) in headers) append(key).append(": ").append(value).append(CRLF)
        // 204 responses must not carry a body; Content-Length is omitted there.
        if (status != 204) append("Content-Length: ").append(body.size).append(CRLF)
        append("Connection: close").append(CRLF).append(CRLF)
    }.toByteArray(StandardCharsets.ISO_8859_1)

    companion object {
        fun empty(status: Int) = Response(status)

        fun text(status: Int, body: String) = Response(
            status,
            listOf("Content-Type" to "text/plain; charset=utf-8"),
            body.toByteArray(StandardCharsets.UTF_8),
        )
    }
}

private const val CRLF = "\r\n"
private const val TOKEN_EXTRA = "!#$%&'*+-.^_`|~"

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

private fun Char.isAsciiAlphanumeric() = this in 'a'..'z' || this in 'A'..'Z' || this in '0'..'9'

private fun Char.isTokenChar() = isAsciiAlphanumeric() || this in TOKEN_EXTRA

private fun String.isToken() = isNotEmpty() && all { it.isTokenChar() }

private fun String.trimSpaceTab() = trim { it == ' ' || it == '\t' }

/**
 * Parses a request head (request line + header fields), given without the
 * terminating blank line and decoded as ISO-8859-1. Returns null if malformed.
 */
fun parseHead(head: String): Request? {
    val lines = head.split(CRLF)
    val requestLine = lines.first()

    // Request line: METHOD SP request-target SP HTTP-version
    val sp1 = requestLine.indexOf(' ')
    if (sp1 < 0) return null
    val sp2 = requestLine.indexOf(' ', sp1 + 1)
    if (sp2 < 0) return null
    val method = requestLine.substring(0, sp1)
    val target = requestLine.substring(sp1 + 1, sp2)
    val version = requestLine.substring(sp2 + 1)
    if (!method.isToken() || target.isEmpty() || !version.startsWith("HTTP/1.")) return null

    val headers = ArrayList<Pair<String, String>>(lines.size - 1)
    for (line in lines.subList(1, lines.size)) {
        val colon = line.indexOf(':')
        if (colon < 0) return null
        val name = line.substring(0, colon)
        if (!name.isToken()) return null
        headers += name to line.substring(colon + 1).trimSpaceTab()
    }
    return Request(method, target, headers)
}
