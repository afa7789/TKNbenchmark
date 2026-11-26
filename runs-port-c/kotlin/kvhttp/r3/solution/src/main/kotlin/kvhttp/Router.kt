// Maps parsed HTTP requests onto key-value store operations.
package kvhttp

const val MAX_KEY_LENGTH = 64
const val MAX_VALUE_LENGTH = 1024 * 1024

class Router(private val store: KvStore) {

    fun route(head: RequestHead, body: ByteArray): Response {
        val path = head.target
        return when {
            path == "/health" ->
                if (head.method == "GET") Response(200, OK_BODY, "text/plain") else Response(405)
            path == "/kv" ->
                if (head.method == "GET") listKeys() else Response(405)
            path.startsWith(KV_PREFIX) -> {
                val key = path.substring(KV_PREFIX.length)
                if (isValidKey(key)) handleKey(head.method, key, body) else Response(400)
            }
            else -> Response(404)
        }
    }

    private fun handleKey(method: String, key: String, body: ByteArray): Response = when (method) {
        "GET" -> store[key]?.let { Response(200, it, "application/octet-stream") } ?: Response(404)
        "PUT" -> Response(if (store.put(key, body)) 201 else 200)
        "DELETE" -> Response(if (store.delete(key)) 204 else 404)
        else -> Response(405)
    }

    /** Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is required. */
    private fun listKeys(): Response {
        val json = store.sortedKeys().joinToString(",", "[", "]") { "\"$it\"" }
        return Response(200, json.toByteArray(Charsets.US_ASCII), "application/json")
    }

    private companion object {
        const val KV_PREFIX = "/kv/"
        val OK_BODY = "ok".toByteArray(Charsets.US_ASCII)

        fun isValidKey(key: String): Boolean =
            key.length in 1..MAX_KEY_LENGTH &&
                key.all { it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it == '_' || it == '-' }
    }
}
