package kvhttp

import java.util.concurrent.ConcurrentHashMap

const val MAX_VALUE_BYTES = 1024 * 1024
private val KEY_RE = Regex("[A-Za-z0-9_-]{1,64}")

/** Thread-safe in-memory key-value store. */
class Store {
    private val map = ConcurrentHashMap<String, ByteArray>()

    operator fun get(key: String): ByteArray? = map[key]

    /** Stores [value]; returns true if [key] was not present before. */
    fun put(key: String, value: ByteArray): Boolean = map.put(key, value) == null

    fun delete(key: String): Boolean = map.remove(key) != null

    fun sortedKeys(): List<String> = map.keys.sorted()
}

/** Routes requests to the key-value API described in SPEC.md. */
class KvApp(private val store: Store = Store()) : Handler {

    override fun handle(request: Request): Response {
        val path = request.target
        return when {
            path == "/health" -> {
                requireMethod(request, "GET")
                Response(200, "ok".toByteArray(), mapOf("Content-Type" to "text/plain; charset=utf-8"))
            }
            path == "/kv" -> {
                requireMethod(request, "GET")
                Response(200, toJsonArray(store.sortedKeys()).toByteArray(), mapOf("Content-Type" to "application/json"))
            }
            path.startsWith("/kv/") -> handleKey(request, path.removePrefix("/kv/"))
            else -> throw HttpError(404)
        }
    }

    private fun handleKey(request: Request, key: String): Response {
        if (!KEY_RE.matches(key)) throw HttpError(400)
        return when (request.method) {
            "GET" -> {
                val value = store[key] ?: throw HttpError(404)
                Response(200, value, mapOf("Content-Type" to "application/octet-stream"))
            }
            "PUT" -> {
                val value = request.body(MAX_VALUE_BYTES)
                Response(if (store.put(key, value)) 201 else 200)
            }
            "DELETE" -> {
                if (!store.delete(key)) throw HttpError(404)
                Response(204)
            }
            else -> throw HttpError(405)
        }
    }

    private fun requireMethod(request: Request, method: String) {
        if (request.method != method) throw HttpError(405)
    }
}

internal fun toJsonArray(items: List<String>): String = buildString {
    append('[')
    items.forEachIndexed { i, s ->
        if (i > 0) append(',')
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
    append(']')
}
