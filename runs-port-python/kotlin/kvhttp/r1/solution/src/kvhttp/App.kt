package kvhttp

import java.util.concurrent.ConcurrentHashMap

private val KEY_RE = Regex("[A-Za-z0-9_-]{1,64}")
private const val KV_PREFIX = "/kv/"

/** Thread-safe in-memory store. */
class KVStore {
    private val data = ConcurrentHashMap<String, ByteArray>()

    /** Stores [value]; returns true if [key] was new. */
    fun put(key: String, value: ByteArray): Boolean = data.put(key, value) == null

    fun get(key: String): ByteArray? = data[key]

    fun delete(key: String): Boolean = data.remove(key) != null

    fun keys(): List<String> = data.keys.sorted()
}

class App(private val store: KVStore = KVStore()) {
    fun handle(req: Request): Response {
        val path = req.path
        return when {
            path == "/health" ->
                if (req.method == "GET") Response(Status.OK, "ok".toByteArray(), mapOf("Content-Type" to "text/plain"))
                else methodNotAllowed("GET")

            path == "/kv" ->
                if (req.method == "GET") Response(Status.OK, keysJson().toByteArray(), mapOf("Content-Type" to "application/json"))
                else methodNotAllowed("GET")

            path.startsWith(KV_PREFIX) -> {
                val key = path.removePrefix(KV_PREFIX)
                if (KEY_RE.matches(key)) handleKey(req, key) else Response(Status.BAD_REQUEST)
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

    // Keys match KEY_RE, so they never need JSON escaping.
    private fun keysJson(): String = store.keys().joinToString(",", "[", "]") { "\"$it\"" }

    private fun methodNotAllowed(allow: String) = Response(Status.METHOD_NOT_ALLOWED, headers = mapOf("Allow" to allow))
}
