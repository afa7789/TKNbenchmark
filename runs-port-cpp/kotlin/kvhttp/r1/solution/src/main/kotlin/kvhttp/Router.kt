package kvhttp

private const val KV_PREFIX = "/kv/"
private const val MAX_KEY_LENGTH = 64

private fun isValidKey(key: String): Boolean =
    key.length in 1..MAX_KEY_LENGTH &&
        key.all { it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it == '_' || it == '-' }

private fun methodNotAllowed(allow: String) = Response.empty(405, "Allow" to allow)

/** Maps requests onto the key/value API described in SPEC.md. */
class Router(private val store: KvStore) {

    fun handle(request: Request): Response {
        val path = request.target
        return when {
            path == "/health" ->
                if (request.method == "GET") Response.text(200, "ok") else methodNotAllowed("GET")
            path == "/kv" ->
                if (request.method == "GET") listKeys() else methodNotAllowed("GET")
            path.startsWith(KV_PREFIX) -> {
                val key = path.removePrefix(KV_PREFIX)
                if (isValidKey(key)) handleKey(request, key) else Response.empty(400)
            }
            else -> Response.empty(404)
        }
    }

    private fun handleKey(request: Request, key: String): Response = when (request.method) {
        "GET" -> store[key]
            ?.let { Response(200, it, listOf("Content-Type" to "application/octet-stream")) }
            ?: Response.empty(404)
        "PUT" -> Response.empty(if (store.put(key, request.body)) 201 else 200)
        "DELETE" -> Response.empty(if (store.remove(key)) 204 else 404)
        else -> methodNotAllowed("GET, PUT, DELETE")
    }

    // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is needed.
    private fun listKeys(): Response =
        Response.text(200, store.keys().joinToString(",", "[", "]") { "\"$it\"" }, "application/json")
}
