package kvhttp

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.ConcurrentSkipListMap
import java.util.concurrent.Executors
import kotlin.system.exitProcess

private const val MAX_VALUE_BYTES = 1 shl 20
private val KEY_PATTERN = Regex("[A-Za-z0-9_-]{1,64}")

/** Thread-safe in-memory store; keys are kept sorted for cheap listing. */
class KvStore {
    private val entries = ConcurrentSkipListMap<String, ByteArray>()

    /** Returns true if the key was newly created. */
    fun put(key: String, value: ByteArray): Boolean = entries.put(key, value) == null
    fun get(key: String): ByteArray? = entries[key]
    fun delete(key: String): Boolean = entries.remove(key) != null
    fun keys(): List<String> = entries.keys.toList()
}

private class Response(val status: Int, val body: ByteArray = ByteArray(0), val contentType: String? = null) {
    companion object {
        fun text(status: Int, text: String) = Response(status, text.toByteArray(), "text/plain; charset=utf-8")
    }
}

class KvServer(private val store: KvStore = KvStore()) {

    fun handle(exchange: HttpExchange) {
        exchange.use {
            val response = try {
                route(it)
            } catch (e: Exception) {
                Response.text(500, "internal error")
            }
            send(it, response)
        }
    }

    private fun route(exchange: HttpExchange): Response {
        val method = exchange.requestMethod
        val path = exchange.requestURI.rawPath ?: ""
        return when {
            path == "/health" -> when (method) {
                "GET" -> Response.text(200, "ok")
                else -> Response(405)
            }
            path == "/kv" -> when (method) {
                "GET" -> listKeys()
                else -> Response(405)
            }
            path.startsWith("/kv/") -> {
                val key = path.removePrefix("/kv/")
                if (!KEY_PATTERN.matches(key)) return Response(400)
                when (method) {
                    "GET" -> store.get(key)?.let { Response(200, it, "application/octet-stream") } ?: Response(404)
                    "PUT" -> putValue(exchange, key)
                    "DELETE" -> if (store.delete(key)) Response(204) else Response(404)
                    else -> Response(405)
                }
            }
            else -> Response(404)
        }
    }

    private fun putValue(exchange: HttpExchange, key: String): Response {
        val declared = exchange.requestHeaders.getFirst("Content-Length")?.trim()?.toLongOrNull()
        if (declared != null && declared > MAX_VALUE_BYTES) return Response(413)
        val body = exchange.requestBody.readNBytes(MAX_VALUE_BYTES + 1)
        if (body.size > MAX_VALUE_BYTES) return Response(413)
        return Response(if (store.put(key, body)) 201 else 200)
    }

    private fun listKeys(): Response {
        val json = store.keys().joinToString(",", "[", "]") { "\"$it\"" }
        return Response(200, json.toByteArray(), "application/json")
    }

    private fun send(exchange: HttpExchange, response: Response) {
        response.contentType?.let { exchange.responseHeaders.set("Content-Type", it) }
        val bodyless = response.status == 204 || exchange.requestMethod == "HEAD"
        val length = if (bodyless || response.body.isEmpty()) -1L else response.body.size.toLong()
        exchange.sendResponseHeaders(response.status, length)
        if (length > 0) exchange.responseBody.write(response.body)
    }

    fun start(port: Int): HttpServer =
        HttpServer.create(InetSocketAddress(InetAddress.getLoopbackAddress(), port), 1024).apply {
            createContext("/", ::handle)
            executor = Executors.newVirtualThreadPerTaskExecutor()
            start()
        }
}

fun main(args: Array<String>) {
    val port = args.singleOrNull()?.toIntOrNull()?.takeIf { it in 1..65535 } ?: run {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }
    KvServer().start(port)
}
