package kvhttp

/** Maps parsed requests onto store operations. */
class Router(private val store: KeyValueStore) {

    fun route(request: HttpRequest): HttpResponse {
        val path = request.target
        return when {
            path == "/health" -> onlyGet(request) { HttpResponse(200, "text/plain", "ok".toByteArray()) }
            path == "/kv" -> onlyGet(request) { listKeys() }
            path.startsWith(KEY_PREFIX) -> {
                val key = path.substring(KEY_PREFIX.length)
                if (isValidKey(key)) handleKey(request, key) else HttpResponse(400)
            }
            else -> HttpResponse(404)
        }
    }

    private inline fun onlyGet(request: HttpRequest, handler: () -> HttpResponse): HttpResponse =
        if (request.method == "GET") handler() else HttpResponse(405)

    private fun listKeys(): HttpResponse {
        // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is needed.
        val json = store.keys().joinToString(separator = ",", prefix = "[", postfix = "]") { "\"$it\"" }
        return HttpResponse(200, "application/json", json.toByteArray(Charsets.US_ASCII))
    }

    private fun handleKey(request: HttpRequest, key: String): HttpResponse = when (request.method) {
        "GET" -> store.get(key)?.let { HttpResponse(200, "application/octet-stream", it) } ?: HttpResponse(404)
        "PUT" -> HttpResponse(if (store.put(key, request.body)) 201 else 200)
        "DELETE" -> HttpResponse(if (store.delete(key)) 204 else 404)
        else -> HttpResponse(405)
    }

    private companion object {
        const val KEY_PREFIX = "/kv/"
    }
}
