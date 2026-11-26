package kvhttp

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpHandler

/** Routes requests for the key-value API. */
class KvHandler(private val store: KvStore) : HttpHandler {

    override fun handle(exchange: HttpExchange) {
        exchange.use {
            val response = try {
                route(it)
            } catch (_: PayloadTooLargeException) {
                Response.empty(413)
            }
            send(it, response)
        }
    }

    private fun route(exchange: HttpExchange): Response {
        val method = exchange.requestMethod
        val path = exchange.requestURI.rawPath

        return when {
            path == "/health" ->
                if (method == "GET") Response.text(200, "ok") else Response.empty(405)

            path == "/kv" ->
                if (method == "GET") listKeys() else Response.empty(405)

            path.startsWith(KV_PREFIX) -> {
                val key = path.removePrefix(KV_PREFIX)
                if (!KEY.matches(key)) return Response.empty(400)
                when (method) {
                    "GET" -> store[key]?.let { Response(200, "application/octet-stream", it) }
                        ?: Response.empty(404)
                    "PUT" -> Response.empty(if (store.put(key, readBody(exchange))) 201 else 200)
                    "DELETE" -> Response.empty(if (store.delete(key)) 204 else 404)
                    else -> Response.empty(405)
                }
            }

            else -> Response.empty(404)
        }
    }

    // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is required.
    private fun listKeys(): Response {
        val json = store.keys().joinToString(separator = ",", prefix = "[", postfix = "]") { "\"$it\"" }
        return Response(200, "application/json", json.toByteArray())
    }

    private fun readBody(exchange: HttpExchange): ByteArray {
        val declared = exchange.requestHeaders.getFirst("Content-Length")?.trim()?.toLongOrNull()
        if (declared != null && declared > MAX_VALUE_BYTES) throw PayloadTooLargeException()

        val body = exchange.requestBody.use { it.readNBytes(MAX_VALUE_BYTES + 1) }
        if (body.size > MAX_VALUE_BYTES) throw PayloadTooLargeException()
        return body
    }

    private fun send(exchange: HttpExchange, response: Response) {
        response.contentType?.let { exchange.responseHeaders.set("Content-Type", it) }
        val body = response.body
        // A length of -1 tells HttpServer there is no body (it emits Content-Length: 0 where allowed).
        exchange.sendResponseHeaders(response.status, if (body.isEmpty()) -1 else body.size.toLong())
        if (body.isNotEmpty()) {
            exchange.responseBody.use { it.write(body) }
        }
    }

    private class Response(val status: Int, val contentType: String?, val body: ByteArray) {
        companion object {
            private val NO_BODY = ByteArray(0)

            fun empty(status: Int) = Response(status, null, NO_BODY)

            fun text(status: Int, text: String) =
                Response(status, "text/plain; charset=utf-8", text.toByteArray())
        }
    }

    private class PayloadTooLargeException : RuntimeException(null, null, false, false)

    companion object {
        const val MAX_VALUE_BYTES = 1 shl 20

        private val KEY = Regex("[A-Za-z0-9_-]{1,64}")
        private const val KV_PREFIX = "/kv/"
    }
}
