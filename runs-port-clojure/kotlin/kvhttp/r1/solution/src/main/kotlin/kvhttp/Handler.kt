package kvhttp

/** A transport-independent HTTP request. */
class Request(val method: String, val path: String, val body: () -> ByteArray = { ByteArray(0) })

/** A transport-independent HTTP response. */
class Response(
    val status: Int,
    val body: ByteArray = ByteArray(0),
    val headers: Map<String, String> = emptyMap(),
)

/** Implements the kvhttp routes on top of a [Store]. */
class Handler(private val store: Store) {

    fun handle(request: Request): Response = when {
        request.path == "/health" -> health(request)
        request.path == "/kv" -> listKeys(request)
        request.path.startsWith(ITEM_PREFIX) -> item(request.path.removePrefix(ITEM_PREFIX), request)
        else -> Response(404)
    }

    private fun health(request: Request): Response =
        if (request.method == "GET") text(200, "ok") else methodNotAllowed("GET")

    private fun listKeys(request: Request): Response {
        if (request.method != "GET") return methodNotAllowed("GET")
        val json = store.keys().joinToString(",", "[", "]", transform = ::jsonString)
        return Response(200, json.toByteArray(), mapOf("Content-Type" to "application/json"))
    }

    private fun item(key: String, request: Request): Response {
        if (!KEY_PATTERN.matches(key)) return Response(400)
        return when (request.method) {
            "GET" -> store.lookup(key)
                ?.let { Response(200, it, mapOf("Content-Type" to "application/octet-stream")) }
                ?: Response(404)
            "PUT" -> Response(if (store.put(key, request.body())) 201 else 200)
            "DELETE" -> Response(if (store.delete(key)) 204 else 404)
            else -> methodNotAllowed("GET, PUT, DELETE")
        }
    }

    private companion object {
        const val ITEM_PREFIX = "/kv/"
        val KEY_PATTERN = Regex("[A-Za-z0-9_-]{1,64}")

        fun text(status: Int, s: String) =
            Response(status, s.toByteArray(), mapOf("Content-Type" to "text/plain; charset=utf-8"))

        fun methodNotAllowed(allowed: String) = Response(405, headers = mapOf("Allow" to allowed))

        fun jsonString(s: String): String = buildString(s.length + 2) {
            append('"')
            for (c in s) {
                when {
                    c == '"' -> append("\\\"")
                    c == '\\' -> append("\\\\")
                    c < ' ' -> append("\\u%04x".format(c.code))
                    else -> append(c)
                }
            }
            append('"')
        }
    }
}
