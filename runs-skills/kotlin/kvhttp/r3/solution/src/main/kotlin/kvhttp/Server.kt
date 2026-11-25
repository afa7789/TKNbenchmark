package kvhttp

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.io.IOException
import java.net.InetSocketAddress
import java.util.concurrent.Executors

const val MAX_VALUE_BYTES = 1 shl 20

private val KEY_PATTERN = Regex("[A-Za-z0-9_-]{1,64}")
private const val KV_PREFIX = "/kv/"

private class HttpError(val status: Int) : Exception(null, null, false, false)

private class Response(
    val status: Int,
    val body: ByteArray = ByteArray(0),
    val contentType: String? = null,
)

class KvServer(private val store: KvStore = KvStore()) {

    fun start(port: Int): HttpServer {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", port), 1024)
        server.executor = Executors.newVirtualThreadPerTaskExecutor()
        server.createContext("/") { exchange -> exchange.use(::handle) }
        server.start()
        return server
    }

    private fun handle(exchange: HttpExchange) {
        val response = try {
            route(exchange)
        } catch (e: HttpError) {
            Response(e.status)
        } catch (e: IOException) {
            return
        }
        send(exchange, response)
    }

    private fun route(exchange: HttpExchange): Response {
        val method = exchange.requestMethod
        val path = exchange.requestURI.rawPath ?: ""
        return when {
            path == "/health" -> when (method) {
                "GET" -> Response(200, "ok".toByteArray(), "text/plain; charset=utf-8")
                else -> Response(405)
            }
            path == "/kv" -> when (method) {
                "GET" -> listKeys()
                else -> Response(405)
            }
            path.startsWith(KV_PREFIX) -> {
                val key = path.substring(KV_PREFIX.length)
                when (method) {
                    "GET", "PUT", "DELETE" -> {
                        if (!KEY_PATTERN.matches(key)) throw HttpError(400)
                        when (method) {
                            "GET" -> store.get(key)
                                ?.let { Response(200, it, "application/octet-stream") }
                                ?: Response(404)
                            "PUT" -> Response(if (store.put(key, readBody(exchange))) 201 else 200)
                            else -> Response(if (store.delete(key)) 204 else 404)
                        }
                    }
                    else -> Response(405)
                }
            }
            else -> Response(404)
        }
    }

    private fun listKeys(): Response {
        // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is needed.
        val json = store.keys().joinToString(",", "[", "]") { "\"$it\"" }
        return Response(200, json.toByteArray(), "application/json")
    }

    private fun readBody(exchange: HttpExchange): ByteArray {
        val declared = exchange.requestHeaders.getFirst("Content-Length")?.trim()
        if (declared != null) {
            val length = declared.toLongOrNull()?.takeIf { it >= 0 } ?: throw HttpError(400)
            if (length > MAX_VALUE_BYTES) throw HttpError(413)
        }
        val body = exchange.requestBody.readNBytes(MAX_VALUE_BYTES + 1)
        if (body.size > MAX_VALUE_BYTES) throw HttpError(413)
        return body
    }

    private fun send(exchange: HttpExchange, response: Response) {
        try {
            response.contentType?.let { exchange.responseHeaders.set("Content-Type", it) }
            exchange.responseHeaders.set("Connection", "close")
            val noBody = response.status == 204 || response.body.isEmpty()
            exchange.sendResponseHeaders(response.status, if (noBody) -1 else response.body.size.toLong())
            if (!noBody) exchange.responseBody.write(response.body)
        } catch (_: IOException) {
            // Client went away; nothing more to do.
        }
    }
}
