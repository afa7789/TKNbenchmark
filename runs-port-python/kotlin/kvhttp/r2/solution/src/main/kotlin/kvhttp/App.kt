package kvhttp

private val KEY_REGEX = Regex("[A-Za-z0-9_-]{1,64}")
private const val KV_PREFIX = "/kv/"

/** Routes requests to the store. Pure request-to-response logic, no I/O. */
class App(private val store: Store) {

    fun handle(request: Request): Response {
        val path = request.path
        return when {
            path == "/health" ->
                if (request.method != "GET") methodNotAllowed("GET")
                else Response(HttpStatus.OK, "ok".toByteArray(), mapOf("Content-Type" to "text/plain"))

            path == "/kv" ->
                if (request.method != "GET") methodNotAllowed("GET")
                else Response(HttpStatus.OK, keysJson().toByteArray(), mapOf("Content-Type" to "application/json"))

            path.startsWith(KV_PREFIX) -> {
                val key = path.removePrefix(KV_PREFIX)
                if (KEY_REGEX.matches(key)) handleKey(request, key) else Response(HttpStatus.BAD_REQUEST)
            }

            else -> Response(HttpStatus.NOT_FOUND)
        }
    }

    private fun handleKey(request: Request, key: String): Response = when (request.method) {
        "GET" -> store.get(key)?.let { Response(HttpStatus.OK, it) } ?: Response(HttpStatus.NOT_FOUND)
        "PUT" -> Response(if (store.put(key, request.body)) HttpStatus.CREATED else HttpStatus.OK)
        "DELETE" -> Response(if (store.delete(key)) HttpStatus.NO_CONTENT else HttpStatus.NOT_FOUND)
        else -> methodNotAllowed("GET, PUT, DELETE")
    }

    // Keys are validated against KEY_REGEX, so none of them needs JSON escaping.
    private fun keysJson(): String = store.keys().joinToString(",", "[", "]") { "\"$it\"" }

    private fun methodNotAllowed(allow: String) =
        Response(HttpStatus.METHOD_NOT_ALLOWED, headers = mapOf("Allow" to allow))
}
