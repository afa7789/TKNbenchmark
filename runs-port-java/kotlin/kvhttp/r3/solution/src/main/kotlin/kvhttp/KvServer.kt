package kvhttp

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.ConcurrentSkipListMap
import java.util.concurrent.Executors
import java.util.logging.Level
import java.util.logging.Logger

/** In-memory HTTP/1.1 key-value server. */
class KvServer {

    private val store = ConcurrentSkipListMap<String, ByteArray>()

    fun start(port: Int): HttpServer =
        HttpServer.create(InetSocketAddress(InetAddress.getLoopbackAddress(), port), BACKLOG).apply {
            executor = Executors.newVirtualThreadPerTaskExecutor()
            createContext("/", ::handle)
            start()
        }

    private fun handle(exchange: HttpExchange) {
        exchange.use {
            val response = try {
                route(it)
            } catch (e: IOException) {
                throw e
            } catch (e: RuntimeException) {
                log.log(Level.WARNING, "request failed", e)
                Response.status(500)
            }
            send(it, response)
        }
    }

    private fun route(exchange: HttpExchange): Response {
        val method = exchange.requestMethod
        val path = exchange.requestURI.rawPath ?: return Response.status(404)
        return when {
            path == "/health" ->
                if (method == "GET") Response.text(200, "ok") else Response.status(405)

            path == "/kv" ->
                if (method == "GET") listKeys() else Response.status(405)

            path.startsWith(KV_PREFIX) -> {
                val key = path.removePrefix(KV_PREFIX)
                if (!KEY.matches(key)) return Response.status(400)
                when (method) {
                    "GET" -> store[key]?.let { Response(200, body = it) } ?: Response.status(404)
                    "PUT" -> put(exchange, key)
                    "DELETE" -> Response.status(if (store.remove(key) == null) 404 else 204)
                    else -> Response.status(405)
                }
            }

            else -> Response.status(404)
        }
    }

    private fun put(exchange: HttpExchange, key: String): Response {
        exchange.requestHeaders.getFirst("Content-Length")?.let { declared ->
            val length = declared.trim().toLongOrNull() ?: return Response.status(400)
            if (length > MAX_VALUE_BYTES) return Response.status(413)
        }
        val value = exchange.requestBody.use { it.readNBytes(MAX_VALUE_BYTES + 1) }
        if (value.size > MAX_VALUE_BYTES) return Response.status(413)
        return Response.status(if (store.put(key, value) == null) 201 else 200)
    }

    // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is needed.
    private fun listKeys(): Response {
        val json = store.keys.joinToString(separator = ",", prefix = "[", postfix = "]") { "\"$it\"" }
        return Response(200, "application/json", json.encodeToByteArray())
    }

    private fun send(exchange: HttpExchange, response: Response) {
        exchange.responseHeaders.apply {
            response.contentType?.let { set("Content-Type", it) }
            set("Connection", "close")
        }
        val body = response.body
        if (response.status == 204 || body.isEmpty()) {
            exchange.sendResponseHeaders(response.status, -1)
        } else {
            exchange.sendResponseHeaders(response.status, body.size.toLong())
            exchange.responseBody.write(body)
        }
    }

    private class Response(val status: Int, val contentType: String? = null, val body: ByteArray = EMPTY) {
        companion object {
            fun status(status: Int) = Response(status)
            fun text(status: Int, text: String) =
                Response(status, "text/plain; charset=utf-8", text.encodeToByteArray())
        }
    }

    private companion object {
        val log: Logger = Logger.getLogger(KvServer::class.java.name)
        val KEY = Regex("[A-Za-z0-9_-]{1,64}")
        const val MAX_VALUE_BYTES = 1 shl 20
        const val KV_PREFIX = "/kv/"
        const val BACKLOG = 1024
        val EMPTY = ByteArray(0)
    }
}
