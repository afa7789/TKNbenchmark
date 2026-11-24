package kvhttp

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import kotlin.system.exitProcess

private const val MAX_VALUE_BYTES = 1 shl 20
private val KEY_PATTERN = Regex("[A-Za-z0-9_-]{1,64}")

/** Thread-safe in-memory key-value store. */
class KvStore {
    private val entries = ConcurrentHashMap<String, ByteArray>()

    /** Stores [value] under [key]; returns true if the key was newly created. */
    fun put(key: String, value: ByteArray): Boolean = entries.put(key, value) == null

    fun get(key: String): ByteArray? = entries[key]

    fun delete(key: String): Boolean = entries.remove(key) != null

    fun sortedKeys(): List<String> = entries.keys.sorted()
}

private class Response(
    val status: Int,
    val body: ByteArray = ByteArray(0),
    val contentType: String? = null,
) {
    companion object {
        fun empty(status: Int) = Response(status)
        fun text(status: Int, text: String) =
            Response(status, text.toByteArray(Charsets.UTF_8), "text/plain; charset=utf-8")
    }
}

class KvHandler(private val store: KvStore) {

    fun handle(exchange: HttpExchange) {
        exchange.use { ex ->
            val response = try {
                route(ex)
            } catch (e: IOException) {
                return
            } catch (e: Exception) {
                Response.text(500, "internal error")
            }
            send(ex, response)
        }
    }

    private fun route(ex: HttpExchange): Response {
        val method = ex.requestMethod.uppercase()
        val path = ex.requestURI.rawPath ?: ""
        return when {
            path == "/health" -> when (method) {
                "GET" -> Response.text(200, "ok")
                else -> Response.empty(405)
            }
            path == "/kv" -> when (method) {
                "GET" -> listKeys()
                else -> Response.empty(405)
            }
            path.startsWith("/kv/") -> {
                val key = path.removePrefix("/kv/")
                if (!KEY_PATTERN.matches(key)) Response.empty(400)
                else handleKey(method, key, ex)
            }
            else -> Response.empty(404)
        }
    }

    private fun handleKey(method: String, key: String, ex: HttpExchange): Response = when (method) {
        "GET" -> store.get(key)?.let { Response(200, it, "application/octet-stream") } ?: Response.empty(404)
        "PUT" -> {
            val body = readBody(ex)
            if (body == null) Response.empty(413)
            else Response.empty(if (store.put(key, body)) 201 else 200)
        }
        "DELETE" -> Response.empty(if (store.delete(key)) 204 else 404)
        else -> Response.empty(405)
    }

    private fun listKeys(): Response {
        val json = store.sortedKeys().joinToString(",", "[", "]") { "\"$it\"" }
        return Response(200, json.toByteArray(Charsets.UTF_8), "application/json")
    }

    /** Reads the request body, or returns null if it exceeds [MAX_VALUE_BYTES]. */
    private fun readBody(ex: HttpExchange): ByteArray? {
        val declared = ex.requestHeaders.getFirst("Content-Length")?.trim()?.toLongOrNull()
        if (declared != null && declared > MAX_VALUE_BYTES) return null
        val bytes = ex.requestBody.readNBytes(MAX_VALUE_BYTES + 1)
        return if (bytes.size > MAX_VALUE_BYTES) null else bytes
    }

    private fun send(ex: HttpExchange, response: Response) {
        response.contentType?.let { ex.responseHeaders.set("Content-Type", it) }
        // A length of -1 tells HttpServer to send "Content-Length: 0" with no body.
        val length = if (response.body.isEmpty()) -1L else response.body.size.toLong()
        ex.sendResponseHeaders(response.status, length)
        if (response.body.isNotEmpty()) ex.responseBody.write(response.body)
    }
}

fun main(args: Array<String>) {
    val port = args.singleOrNull()?.toIntOrNull()?.takeIf { it in 1..65535 } ?: run {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }
    val handler = KvHandler(KvStore())
    val server = HttpServer.create(InetSocketAddress(InetAddress.getLoopbackAddress(), port), 1024)
    server.createContext("/", handler::handle)
    server.executor = Executors.newVirtualThreadPerTaskExecutor()
    server.start()
}
