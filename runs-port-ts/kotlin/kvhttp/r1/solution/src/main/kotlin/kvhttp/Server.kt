package kvhttp

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.io.IOException
import java.net.InetSocketAddress
import java.util.concurrent.Executors

const val MAX_VALUE_BYTES = 1024 * 1024
private const val KV_PREFIX = "/kv/"
private const val BACKLOG = 511
private val KEY_PATTERN = Regex("^[A-Za-z0-9_-]{1,64}$")

private class HttpError(val status: Int) : Exception("HTTP $status")

/** HTTP front end for a [KvStore]. */
class KvServer(private val store: KvStore = KvStore()) {

    fun start(host: String, port: Int): HttpServer =
        HttpServer.create(InetSocketAddress(host, port), BACKLOG).apply {
            createContext("/") { exchange -> exchange.use(::dispatch) }
            executor = Executors.newVirtualThreadPerTaskExecutor()
            start()
        }

    private fun dispatch(exchange: HttpExchange) {
        try {
            handle(exchange)
        } catch (e: HttpError) {
            exchange.responseHeaders.set("Connection", "close")
            exchange.send(e.status)
        } catch (e: IOException) {
            // Client went away mid-request; nothing left to answer.
        } catch (e: Exception) {
            System.err.println("internal error: $e")
            runCatching { exchange.send(500) }
        }
    }

    private fun handle(exchange: HttpExchange) {
        val method = exchange.requestMethod
        val path = exchange.requestURI.rawPath ?: "/"

        when {
            path == "/health" -> when (method) {
                "GET" -> exchange.send(200, "ok".toByteArray(), "text/plain; charset=utf-8")
                else -> exchange.methodNotAllowed("GET")
            }

            path == "/kv" -> when (method) {
                "GET" -> exchange.send(200, keysJson().toByteArray(), "application/json")
                else -> exchange.methodNotAllowed("GET")
            }

            path.startsWith(KV_PREFIX) -> {
                val key = path.removePrefix(KV_PREFIX)
                if (!KEY_PATTERN.matches(key)) return exchange.send(400)
                when (method) {
                    "GET" -> store[key]
                        ?.let { exchange.send(200, it, "application/octet-stream") }
                        ?: exchange.send(404)
                    "PUT" -> exchange.send(if (store.set(key, exchange.readBody(MAX_VALUE_BYTES))) 201 else 200)
                    "DELETE" -> exchange.send(if (store.delete(key)) 204 else 404)
                    else -> exchange.methodNotAllowed("GET", "PUT", "DELETE")
                }
            }

            else -> exchange.send(404)
        }
    }

    /** Keys are restricted to `[A-Za-z0-9_-]`, so they need no JSON escaping. */
    private fun keysJson(): String = store.keys().joinToString(",", "[", "]") { "\"$it\"" }
}

private fun HttpExchange.readBody(limit: Int): ByteArray {
    val declared = requestHeaders.getFirst("Content-Length")?.trim()?.toLongOrNull() ?: 0L
    if (declared > limit) throw HttpError(413)
    val body = requestBody.readNBytes(limit + 1)
    if (body.size > limit) throw HttpError(413)
    return body
}

private fun HttpExchange.methodNotAllowed(vararg allowed: String) {
    responseHeaders.set("Allow", allowed.joinToString(", "))
    send(405)
}

/** Sends a response with an exact Content-Length (never chunked). */
private fun HttpExchange.send(status: Int, body: ByteArray = ByteArray(0), contentType: String? = null) {
    contentType?.let { responseHeaders.set("Content-Type", it) }
    // A length of -1 tells HttpServer there is no body; it then emits Content-Length: 0
    // (or omits it for 204), whereas 0 would select chunked encoding.
    sendResponseHeaders(status, if (body.isEmpty()) -1 else body.size.toLong())
    if (body.isNotEmpty()) responseBody.use { it.write(body) }
}
