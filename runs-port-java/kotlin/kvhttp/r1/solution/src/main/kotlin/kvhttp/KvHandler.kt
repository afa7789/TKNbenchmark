package kvhttp

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpHandler
import java.util.logging.Level
import java.util.logging.Logger

/** Routes and serves all requests for the key-value HTTP API. */
class KvHandler(private val store: KvStore) : HttpHandler {

    override fun handle(exchange: HttpExchange) {
        exchange.use {
            val response = try {
                route(it)
            } catch (_: PayloadTooLargeException) {
                Response.status(413)
            } catch (e: RuntimeException) {
                log.log(Level.WARNING, "Unhandled error serving request", e)
                Response.status(500)
            }
            send(it, response)
        }
    }

    private fun route(exchange: HttpExchange): Response {
        val method = exchange.requestMethod
        val path = exchange.requestURI.rawPath

        return when {
            path == "/health" -> requireGet(method) { Response.text(200, "ok") }
            path == "/kv" -> requireGet(method, ::listKeys)
            path.startsWith(KV_PREFIX) -> {
                val key = path.removePrefix(KV_PREFIX)
                if (!KEY.matches(key)) return Response.status(400)
                when (method) {
                    "GET" -> store[key]?.let { Response(200, "application/octet-stream", it) } ?: Response.status(404)
                    "PUT" -> Response.status(if (store.put(key, readBody(exchange))) 201 else 200)
                    "DELETE" -> Response.status(if (store.delete(key)) 204 else 404)
                    else -> Response.status(405)
                }
            }
            else -> Response.status(404)
        }
    }

    private inline fun requireGet(method: String, action: () -> Response): Response =
        if (method == "GET") action() else Response.status(405)

    private fun listKeys(): Response {
        // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is required.
        val json = store.keys().joinToString(separator = ",", prefix = "[", postfix = "]") { "\"$it\"" }
        return Response(200, "application/json", json.toByteArray())
    }

    private fun readBody(exchange: HttpExchange): ByteArray {
        val declared = exchange.requestHeaders.getFirst("Content-Length")?.trim()?.toLongOrNull()
        if (declared != null && declared > MAX_VALUE_BYTES) throw PayloadTooLargeException()

        return exchange.requestBody.use { input ->
            input.readNBytes(MAX_VALUE_BYTES + 1).also {
                if (it.size > MAX_VALUE_BYTES) throw PayloadTooLargeException()
            }
        }
    }

    private fun send(exchange: HttpExchange, response: Response) {
        response.contentType?.let { exchange.responseHeaders.set("Content-Type", it) }
        val body = response.body
        val bodyForbidden = response.status == 204 || exchange.requestMethod == "HEAD"
        if (bodyForbidden || body.isEmpty()) {
            // -1 tells HttpServer there is no body; it emits Content-Length: 0 where permitted.
            exchange.sendResponseHeaders(response.status, -1)
            return
        }
        exchange.sendResponseHeaders(response.status, body.size.toLong())
        exchange.responseBody.use { it.write(body) }
    }

    private class Response(val status: Int, val contentType: String?, val body: ByteArray) {
        companion object {
            private val NO_BODY = ByteArray(0)

            fun status(status: Int) = Response(status, null, NO_BODY)

            fun text(status: Int, text: String) = Response(status, "text/plain; charset=utf-8", text.toByteArray())
        }
    }

    private class PayloadTooLargeException : RuntimeException(null, null, false, false)

    companion object {
        const val MAX_VALUE_BYTES = 1 shl 20

        private const val KV_PREFIX = "/kv/"
        private val KEY = Regex("[A-Za-z0-9_-]{1,64}")
        private val log: Logger = Logger.getLogger(KvHandler::class.java.name)
    }
}
