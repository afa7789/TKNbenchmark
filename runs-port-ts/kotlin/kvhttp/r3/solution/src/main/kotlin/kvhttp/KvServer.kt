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
private const val TEXT_PLAIN = "text/plain; charset=utf-8"

private class HttpError(
    val status: Int,
    message: String = reasonPhrase(status),
    val headers: Map<String, String> = emptyMap(),
) : Exception(message)

private fun reasonPhrase(status: Int): String = when (status) {
    400 -> "Bad Request"
    404 -> "Not Found"
    405 -> "Method Not Allowed"
    413 -> "Payload Too Large"
    500 -> "Internal Server Error"
    else -> "Error"
}

private fun methodNotAllowed(vararg allowed: String): Nothing =
    throw HttpError(405, headers = mapOf("Allow" to allowed.joinToString(", ")))

/** HTTP front end for a [KvStore]; one request per connection is sufficient but keep-alive works too. */
class KvServer(
    private val store: KvStore = KvStore(),
    private val port: Int,
    private val host: String = "127.0.0.1",
) : AutoCloseable {
    private val executor: ExecutorService = Executors.newVirtualThreadPerTaskExecutor()
    private val server: HttpServer = HttpServer.create(InetSocketAddress(host, port), BACKLOG).apply {
        createContext("/") { exchange -> exchange.use(::handle) }
        executor = this@KvServer.executor
    }

    fun start() = server.start()

    override fun close() {
        server.stop(0)
        executor.shutdownNow()
    }

    private fun handle(exchange: HttpExchange) {
        try {
            route(exchange)
        } catch (e: HttpError) {
            exchange.responseHeaders.apply { e.headers.forEach { (name, value) -> set(name, value) } }
            if (e.status == 413) exchange.responseHeaders.set("Connection", "close")
            exchange.send(e.status, e.message.orEmpty().toByteArray())
        } catch (e: IOException) {
            throw e
        } catch (e: Exception) {
            System.err.println("internal error: $e")
            exchange.send(500, "internal error".toByteArray())
        }
    }

    private fun route(exchange: HttpExchange) {
        val method = exchange.requestMethod
        val path = exchange.requestURI.rawPath ?: "/"

        when {
            path == "/health" -> {
                if (method != "GET") methodNotAllowed("GET")
                exchange.send(200, "ok".toByteArray())
            }

            path == "/kv" -> {
                if (method != "GET") methodNotAllowed("GET")
                exchange.send(200, toJsonArray(store.keys()).toByteArray(), "application/json")
            }

            path.startsWith(KV_PREFIX) -> {
                val key = path.removePrefix(KV_PREFIX)
                if (!KEY_PATTERN.matches(key)) throw HttpError(400, "invalid key")
                when (method) {
                    "GET" -> {
                        val value = store[key] ?: throw HttpError(404)
                        exchange.send(200, value, "application/octet-stream")
                    }

                    "PUT" -> {
                        val value = exchange.readBody(MAX_VALUE_BYTES)
                        exchange.send(if (store.set(key, value)) 201 else 200)
                    }

                    "DELETE" -> {
                        if (!store.delete(key)) throw HttpError(404)
                        exchange.send(204)
                    }

                    else -> methodNotAllowed("GET", "PUT", "DELETE")
                }
            }

            else -> throw HttpError(404)
        }
    }

    private companion object {
        const val BACKLOG = 511
    }
}

private fun HttpExchange.readBody(limit: Int): ByteArray {
    val declared = requestHeaders.getFirst("Content-Length")?.trim()?.toLongOrNull()
    if (declared != null && declared > limit) throw HttpError(413)
    val body = requestBody.readNBytes(limit + 1)
    if (body.size > limit) throw HttpError(413)
    return body
}

private fun HttpExchange.send(status: Int, body: ByteArray = ByteArray(0), contentType: String = TEXT_PLAIN) {
    if (body.isNotEmpty()) responseHeaders.set("Content-Type", contentType)
    // HEAD responses never carry a body; HttpServer derives their framing itself.
    val payload = if (requestMethod == "HEAD") ByteArray(0) else body
    // A length of -1 tells HttpServer there is no body (it still emits Content-Length: 0 where allowed).
    sendResponseHeaders(status, if (payload.isEmpty()) -1 else payload.size.toLong())
    if (payload.isNotEmpty()) responseBody.use { it.write(payload) }
}

/** Keys are restricted to `[A-Za-z0-9_-]`, so no JSON escaping is ever required. */
private fun toJsonArray(keys: List<String>): String =
    keys.joinToString(separator = ",", prefix = "[", postfix = "]") { "\"$it\"" }
