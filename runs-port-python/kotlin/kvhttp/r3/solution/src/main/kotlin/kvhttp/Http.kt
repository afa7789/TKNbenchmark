package kvhttp

/** The subset of HTTP status codes this server produces. */
enum class Status(val code: Int, val phrase: String) {
    OK(200, "OK"),
    CREATED(201, "Created"),
    NO_CONTENT(204, "No Content"),
    BAD_REQUEST(400, "Bad Request"),
    NOT_FOUND(404, "Not Found"),
    METHOD_NOT_ALLOWED(405, "Method Not Allowed"),
    CONTENT_TOO_LARGE(413, "Content Too Large"),
    REQUEST_HEADER_FIELDS_TOO_LARGE(431, "Request Header Fields Too Large"),
    NOT_IMPLEMENTED(501, "Not Implemented"),
}

/** Signals a request that must be answered with [status] instead of being routed. */
class HttpException(val status: Status) : Exception(status.phrase)

class Request(
    val method: String,
    val path: String,
    /** Header names are lower-cased; a repeated header keeps its last value. */
    val headers: Map<String, String>,
    val body: ByteArray = EMPTY_BODY,
)

class Response(
    val status: Status,
    val body: ByteArray = EMPTY_BODY,
    val headers: Map<String, String> = emptyMap(),
) {
    /** Serializes the response; the connection is always closed after it. */
    fun encode(): ByteArray {
        val head = buildString {
            append("HTTP/1.1 ").append(status.code).append(' ').append(status.phrase).append("\r\n")
            val all = headers + mapOf("Content-Length" to body.size.toString(), "Connection" to "close")
            for ((name, value) in all) append(name).append(": ").append(value).append("\r\n")
            append("\r\n")
        }
        return head.toByteArray(Charsets.ISO_8859_1) + body
    }
}

internal val EMPTY_BODY = ByteArray(0)
