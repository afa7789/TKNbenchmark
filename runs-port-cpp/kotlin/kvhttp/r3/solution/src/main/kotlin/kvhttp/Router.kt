package kvhttp

private const val KV_PREFIX = "/kv/"
private const val MAX_KEY_LENGTH = 64

private fun statusOnly(status: Int) = Response(status)

/** True if [key] matches `[A-Za-z0-9_-]{1,64}`. */
fun isValidKey(key: String): Boolean =
    key.length in 1..MAX_KEY_LENGTH &&
        key.all { it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it == '_' || it == '-' }

// Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is ever required.
private fun jsonStringArray(items: List<String>): String =
    items.joinToString(separator = ",", prefix = "[", postfix = "]") { "\"$it\"" }

/** Maps requests onto the key/value API. */
class Router(private val store: Store) {
    fun handle(request: Request): Response {
        val path = request.target
        return when {
            path == "/health" ->
                if (request.method != "GET") statusOnly(405)
                else Response(200, "text/plain", "ok".toByteArray())

            path == "/kv" ->
                if (request.method != "GET") statusOnly(405)
                else Response(200, "application/json", jsonStringArray(store.keys()).toByteArray())

            path.startsWith(KV_PREFIX) -> {
                val key = path.substring(KV_PREFIX.length)
                if (!isValidKey(key)) statusOnly(400) else handleKey(request, key)
            }

            else -> statusOnly(404)
        }
    }

    private fun handleKey(request: Request, key: String): Response = when (request.method) {
        "GET" -> store[key]?.let { Response(200, "application/octet-stream", it) } ?: statusOnly(404)
        "PUT" -> statusOnly(if (store.put(key, request.body)) 201 else 200)
        "DELETE" -> statusOnly(if (store.remove(key)) 204 else 404)
        else -> statusOnly(405)
    }
}
