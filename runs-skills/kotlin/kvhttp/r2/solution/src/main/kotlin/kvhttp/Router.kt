package kvhttp

/** A fully materialised HTTP response. */
class Response(
    val status: Int,
    val body: ByteArray = ByteArray(0),
    val contentType: String? = null,
) {
    companion object {
        fun text(status: Int, text: String = "") =
            Response(status, text.encodeToByteArray(), if (text.isEmpty()) null else "text/plain; charset=utf-8")

        fun json(status: Int, json: String) =
            Response(status, json.encodeToByteArray(), "application/json")
    }
}

private val KEY_PATTERN = Regex("[A-Za-z0-9_-]{1,64}")

fun isValidKey(key: String): Boolean = KEY_PATTERN.matches(key)

/** Maps requests onto [store] operations. Pure with respect to I/O, so it is easy to test. */
class Router(private val store: KvStore) {

    fun handle(method: String, path: String, body: ByteArray): Response = when {
        path == "/health" -> when (method) {
            "GET" -> Response.text(200, "ok")
            else -> methodNotAllowed()
        }
        path == "/kv" -> when (method) {
            "GET" -> Response.json(200, store.keys().joinToString(",", "[", "]") { "\"$it\"" })
            else -> methodNotAllowed()
        }
        path.startsWith(KV_PREFIX) -> handleKey(method, path.removePrefix(KV_PREFIX), body)
        else -> Response.text(404, "not found")
    }

    private fun handleKey(method: String, key: String, body: ByteArray): Response {
        if (!isValidKey(key)) return Response.text(400, "invalid key")
        return when (method) {
            "GET" -> store[key]?.let { Response(200, it, "application/octet-stream") } ?: notFound()
            "PUT" -> Response(if (store.put(key, body)) 201 else 200)
            "DELETE" -> if (store.delete(key)) Response(204) else notFound()
            else -> methodNotAllowed()
        }
    }

    private fun notFound() = Response.text(404, "not found")

    private fun methodNotAllowed() = Response.text(405, "method not allowed")

    private companion object {
        const val KV_PREFIX = "/kv/"
    }
}
