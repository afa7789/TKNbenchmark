package kvhttp

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.ConcurrentSkipListMap
import java.util.concurrent.Executors
import kotlin.system.exitProcess

private const val MAX_VALUE_BYTES = 1 shl 20
private val KEY_PATTERN = Regex("[A-Za-z0-9_-]{1,64}")
private const val KV_PREFIX = "/kv/"

/** Thread-safe in-memory store; keys are kept sorted so listing is cheap. */
class KeyValueStore {
    private val entries = ConcurrentSkipListMap<String, ByteArray>()

    /** Stores [value] under [key]; returns true if the key was new. */
    fun put(key: String, value: ByteArray): Boolean = entries.put(key, value) == null

    fun get(key: String): ByteArray? = entries[key]

    fun delete(key: String): Boolean = entries.remove(key) != null

    fun keys(): List<String> = entries.keys.toList()
}

private class Response(
    val status: Int,
    val body: ByteArray = ByteArray(0),
    val contentType: String? = null,
    val allow: String? = null,
) {
    companion object {
        fun empty(status: Int) = Response(status)
        fun text(status: Int, text: String) = Response(status, text.toByteArray(), "text/plain; charset=utf-8")
    }
}

class KvHandler(private val store: KeyValueStore) {

    fun handle(exchange: HttpExchange) {
        exchange.use {
            val response = try {
                route(exchange)
            } catch (_: IOException) {
                return // client went away mid-request; nothing to answer
            } catch (_: Exception) {
                Response.text(500, "internal error")
            }
            send(exchange, response)
        }
    }

    private fun route(exchange: HttpExchange): Response {
        val method = exchange.requestMethod
        val path = exchange.requestURI.rawPath ?: ""
        return when {
            path == "/health" -> when (method) {
                "GET" -> Response.text(200, "ok")
                else -> methodNotAllowed("GET")
            }
            path == "/kv" -> when (method) {
                "GET" -> listKeys()
                else -> methodNotAllowed("GET")
            }
            path.startsWith(KV_PREFIX) -> {
                val key = path.substring(KV_PREFIX.length)
                if (!KEY_PATTERN.matches(key)) return Response.text(400, "invalid key")
                when (method) {
                    "GET" -> store.get(key)?.let { Response(200, it, "application/octet-stream") }
                        ?: Response.text(404, "not found")
                    "PUT" -> putValue(exchange, key)
                    "DELETE" -> if (store.delete(key)) Response.empty(204) else Response.text(404, "not found")
                    else -> methodNotAllowed("GET, PUT, DELETE")
                }
            }
            else -> Response.text(404, "not found")
        }
    }

    private fun methodNotAllowed(allow: String): Response =
        Response(405, "method not allowed".toByteArray(), "text/plain; charset=utf-8", allow)

    private fun listKeys(): Response {
        val json = store.keys().joinToString(separator = ",", prefix = "[", postfix = "]") { "\"$it\"" }
        return Response(200, json.toByteArray(), "application/json")
    }

    private fun putValue(exchange: HttpExchange, key: String): Response {
        val declared = exchange.requestHeaders.getFirst("Content-Length")?.trim()?.toLongOrNull()
        if (declared != null && declared > MAX_VALUE_BYTES) return Response.text(413, "value too large")
        val body = exchange.requestBody.use { it.readNBytes(MAX_VALUE_BYTES + 1) }
        if (body.size > MAX_VALUE_BYTES) return Response.text(413, "value too large")
        return Response.empty(if (store.put(key, body)) 201 else 200)
    }

    private fun send(exchange: HttpExchange, response: Response) {
        val headers = exchange.responseHeaders
        response.contentType?.let { headers["Content-Type"] = it }
        response.allow?.let { headers["Allow"] = it }
        // A length of -1 tells HttpServer there is no body (it emits Content-Length: 0, or none for 204).
        val length = if (response.body.isEmpty()) -1L else response.body.size.toLong()
        exchange.sendResponseHeaders(response.status, length)
        if (response.body.isNotEmpty()) exchange.responseBody.write(response.body)
    }
}

fun main(args: Array<String>) {
    val port = args.singleOrNull()?.toIntOrNull()?.takeIf { it in 1..65535 } ?: run {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }
    val handler = KvHandler(KeyValueStore())
    val server = HttpServer.create(InetSocketAddress(InetAddress.getLoopbackAddress(), port), 1024)
    server.executor = Executors.newVirtualThreadPerTaskExecutor()
    server.createContext("/") { handler.handle(it) }
    server.start()
}
