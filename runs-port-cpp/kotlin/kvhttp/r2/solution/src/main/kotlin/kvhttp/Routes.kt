package kvhttp

private const val KV_PREFIX = "/kv/"
private const val MAX_KEY_LENGTH = 64

/** Returns true if [key] matches `[A-Za-z0-9_-]{1,64}`. */
fun isValidKey(key: String): Boolean =
    key.length in 1..MAX_KEY_LENGTH &&
        key.all { it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it == '_' || it == '-' }

/** Dispatches requests against the key-value API. */
class Router(private val store: KvStore) : (Request) -> Response {
    override fun invoke(request: Request): Response {
        val path = request.target
        return when {
            path == "/health" -> handleHealth(request)
            path == "/kv" -> handleList(request)
            path.startsWith(KV_PREFIX) -> handleKey(request, path.substring(KV_PREFIX.length))
            else -> Response.text(404, "not found")
        }
    }

    private fun handleHealth(request: Request): Response =
        if (request.method != "GET") methodNotAllowed("GET") else Response.text(200, "ok")

    private fun handleList(request: Request): Response {
        if (request.method != "GET") return methodNotAllowed("GET")
        // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is required.
        val body = store.keys().joinToString(",", "[", "]") { "\"$it\"" }
        return Response(200, listOf("Content-Type" to "application/json"), body.toByteArray(Charsets.US_ASCII))
    }

    private fun handleKey(request: Request, key: String): Response {
        if (!isValidKey(key)) return Response.text(400, "invalid key")
        return when (request.method) {
            "GET" -> store[key]
                ?.let { Response(200, listOf("Content-Type" to "application/octet-stream"), it) }
                ?: Response.text(404, "not found")
            "PUT" -> when (store.put(key, request.body)) {
                KvStore.PutResult.CREATED -> Response.empty(201)
                KvStore.PutResult.REPLACED -> Response.empty(200)
            }
            "DELETE" -> if (store.remove(key)) Response.empty(204) else Response.text(404, "not found")
            else -> methodNotAllowed("GET, PUT, DELETE")
        }
    }

    private fun methodNotAllowed(allow: String): Response {
        val base = Response.text(405, "Method Not Allowed")
        return Response(base.status, base.headers + ("Allow" to allow), base.body)
    }
}
