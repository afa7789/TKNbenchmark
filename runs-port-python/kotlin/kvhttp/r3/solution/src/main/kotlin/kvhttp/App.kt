package kvhttp

import java.util.concurrent.ConcurrentHashMap

private val KEY_REGEX = Regex("[A-Za-z0-9_-]{1,64}")

/** Thread-safe in-memory key-value store. */
class Store {
    private val data = ConcurrentHashMap<String, ByteArray>()

    /** Stores [value] under [key]; returns true if the key was newly created. */
    fun put(key: String, value: ByteArray): Boolean = data.put(key, value) == null

    fun get(key: String): ByteArray? = data[key]

    fun delete(key: String): Boolean = data.remove(key) != null

    fun keys(): List<String> = data.keys.sorted()
}

/** Routes requests to the store. Pure request-to-response logic with no I/O. */
class App(private val store: Store = Store()) {

    fun handle(req: Request): Response {
        val path = req.path
        return when {
            path == "/health" ->
                if (req.method != "GET") methodNotAllowed("GET")
                else Response(Status.OK, "ok".toByteArray(), mapOf("Content-Type" to "text/plain; charset=utf-8"))

            path == "/kv" ->
                if (req.method != "GET") methodNotAllowed("GET")
                else Response(Status.OK, keysJson().toByteArray(), mapOf("Content-Type" to "application/json"))

            path.startsWith("/kv/") -> {
                val key = path.removePrefix("/kv/")
                if (KEY_REGEX.matches(key)) handleKey(req, key) else Response(Status.BAD_REQUEST)
            }

            else -> Response(Status.NOT_FOUND)
        }
    }

    private fun handleKey(req: Request, key: String): Response = when (req.method) {
        "GET" -> store.get(key)
            ?.let { Response(Status.OK, it, mapOf("Content-Type" to "application/octet-stream")) }
            ?: Response(Status.NOT_FOUND)

        "PUT" -> Response(if (store.put(key, req.body)) Status.CREATED else Status.OK)

        "DELETE" -> Response(if (store.delete(key)) Status.NO_CONTENT else Status.NOT_FOUND)

        else -> methodNotAllowed("GET, PUT, DELETE")
    }

    // Keys are restricted to [A-Za-z0-9_-], so they never need JSON escaping.
    private fun keysJson(): String = store.keys().joinToString(",", "[", "]") { "\"$it\"" }

    private fun methodNotAllowed(allow: String) = Response(Status.METHOD_NOT_ALLOWED, headers = mapOf("Allow" to allow))
}
