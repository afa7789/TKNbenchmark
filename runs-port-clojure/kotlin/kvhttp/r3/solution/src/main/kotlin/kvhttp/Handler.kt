package kvhttp

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpHandler

/** HTTP handler implementing the kvhttp routes on top of a [Store]. */
class KvHandler(private val store: Store) : HttpHandler {

    private class Response(
        val status: Int,
        val body: ByteArray = EMPTY,
        val contentType: String? = null,
    )

    override fun handle(exchange: HttpExchange) {
        exchange.use {
            val response = try {
                route(exchange)
            } catch (e: Exception) {
                System.err.println("kvhttp: error handling ${exchange.requestMethod} ${exchange.requestURI}: $e")
                Response(500)
            }
            send(exchange, response)
        }
    }

    private fun route(exchange: HttpExchange): Response {
        val path = exchange.requestURI.rawPath ?: ""
        val method = exchange.requestMethod
        return when {
            path == "/health" -> health(method)
            path == "/kv" -> listKeys(method)
            path.startsWith(KV_PREFIX) -> {
                val key = path.substring(KV_PREFIX.length)
                if (KEY_PATTERN.matches(key)) entry(method, key, exchange) else Response(400)
            }
            else -> Response(404)
        }
    }

    private fun health(method: String): Response =
        if (method == "GET") Response(200, "ok".toByteArray(), "text/plain") else Response(405)

    private fun listKeys(method: String): Response {
        if (method != "GET") return Response(405)
        val json = store.keys().joinToString(",", "[", "]") { jsonString(it) }
        return Response(200, json.toByteArray(), "application/json")
    }

    private fun entry(method: String, key: String, exchange: HttpExchange): Response = when (method) {
        "GET" -> store[key]?.let { Response(200, it, "application/octet-stream") } ?: Response(404)
        "PUT" -> {
            val value = exchange.requestBody.use { it.readAllBytes() }
            when (store.put(key, value)) {
                PutResult.CREATED -> Response(201)
                PutResult.REPLACED -> Response(200)
            }
        }
        "DELETE" -> if (store.delete(key)) Response(204) else Response(404)
        else -> Response(405)
    }

    private fun send(exchange: HttpExchange, response: Response) {
        response.contentType?.let { exchange.responseHeaders["Content-Type"] = listOf(it) }
        // A length of -1 tells HttpServer there is no body and emits `Content-Length: 0`
        // (or no length at all for 204); 0 would switch to chunked encoding instead.
        val length = if (response.body.isEmpty()) -1L else response.body.size.toLong()
        exchange.sendResponseHeaders(response.status, length)
        if (response.body.isNotEmpty()) {
            exchange.responseBody.write(response.body)
        }
    }

    private companion object {
        const val KV_PREFIX = "/kv/"
        val KEY_PATTERN = Regex("[A-Za-z0-9_-]{1,64}")
        val EMPTY = ByteArray(0)

        fun jsonString(s: String): String = buildString(s.length + 2) {
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
    }
}
