package kvhttp

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.io.IOException
import java.net.InetSocketAddress
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

const val MAX_VALUE_BYTES = 1024 * 1024

private val KEY_PATTERN = Regex("[A-Za-z0-9_-]{1,64}")
private const val KV_PREFIX = "/kv/"

private class PayloadTooLargeException : IOException("payload too large")

private val EMPTY = ByteArray(0)

/** HTTP front end exposing a [KvStore] as described in SPEC.md. */
class KvServer(
    private val store: KvStore = KvStore(),
) : AutoCloseable {
    private val executor: ExecutorService = Executors.newVirtualThreadPerTaskExecutor()
    private var server: HttpServer? = null

    fun start(port: Int, host: String = "127.0.0.1", backlog: Int = 1024) {
        check(server == null) { "server already started" }
        server = HttpServer.create(InetSocketAddress(host, port), backlog).apply {
            executor = this@KvServer.executor
            createContext("/") { exchange -> exchange.use(::handle) }
            start()
        }
    }

    override fun close() {
        server?.stop(0)
        server = null
        executor.shutdownNow()
    }

    private fun handle(exchange: HttpExchange) {
        // Every response closes the connection; any unread body is discarded.
        exchange.responseHeaders["Connection"] = "close"
        try {
            route(exchange)
        } catch (_: PayloadTooLargeException) {
            exchange.send(413)
        } catch (e: IOException) {
            throw e
        } catch (e: Exception) {
            System.err.println("request failed: $e")
            exchange.send(500)
        }
    }

    private fun route(exchange: HttpExchange) {
        val path = exchange.requestURI.rawPath ?: "/"
        when {
            path == "/health" ->
                if (exchange.requestMethod == "GET") {
                    exchange.send(200, "ok".toByteArray(), "text/plain")
                } else {
                    exchange.methodNotAllowed("GET")
                }

            path == "/kv" ->
                if (exchange.requestMethod == "GET") {
                    exchange.send(200, keysJson().toByteArray(), "application/json")
                } else {
                    exchange.methodNotAllowed("GET")
                }

            path.startsWith(KV_PREFIX) -> {
                val key = path.removePrefix(KV_PREFIX)
                if (KEY_PATTERN.matches(key)) handleKey(exchange, key) else exchange.send(400)
            }

            else -> exchange.send(404)
        }
    }

    private fun handleKey(exchange: HttpExchange, key: String) {
        when (exchange.requestMethod) {
            "GET" -> {
                val value = store[key]
                if (value == null) exchange.send(404) else exchange.send(200, value, "application/octet-stream")
            }

            "PUT" -> {
                val value = exchange.readBody(MAX_VALUE_BYTES)
                exchange.send(if (store.put(key, value)) 201 else 200)
            }

            "DELETE" -> exchange.send(if (store.delete(key)) 204 else 404)
            else -> exchange.methodNotAllowed("GET", "PUT", "DELETE")
        }
    }

    // Keys are validated against KEY_PATTERN, so they never need JSON escaping.
    private fun keysJson(): String = store.keys().joinToString(",", "[", "]") { "\"$it\"" }
}

private fun HttpExchange.methodNotAllowed(vararg allowed: String) {
    responseHeaders["Allow"] = allowed.joinToString(", ")
    send(405)
}

/** Writes a complete response with an exact Content-Length (none for 204). */
private fun HttpExchange.send(status: Int, body: ByteArray = EMPTY, contentType: String? = null) {
    contentType?.let { responseHeaders["Content-Type"] = it }
    // A length of -1 tells HttpServer there is no body; it still emits "Content-Length: 0" where allowed.
    sendResponseHeaders(status, if (body.isEmpty()) -1 else body.size.toLong())
    if (body.isNotEmpty()) responseBody.write(body)
}

/** Reads the full request body, rejecting bodies larger than [limit] bytes. */
private fun HttpExchange.readBody(limit: Int): ByteArray {
    val declared = requestHeaders.getFirst("Content-Length")?.trim()?.toLongOrNull()
    if (declared != null && declared > limit) throw PayloadTooLargeException()
    val body = requestBody.readNBytes(limit + 1)
    if (body.size > limit) throw PayloadTooLargeException()
    return body
}
