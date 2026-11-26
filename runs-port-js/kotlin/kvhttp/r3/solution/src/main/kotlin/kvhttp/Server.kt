package kvhttp

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.InetSocketAddress
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

const val MAX_VALUE_BYTES = 1024 * 1024

private val KEY_RE = Regex("^[A-Za-z0-9_-]{1,64}$")

private val REASONS = mapOf(
    400 to "Bad Request",
    404 to "Not Found",
    405 to "Method Not Allowed",
    411 to "Length Required",
    413 to "Payload Too Large",
    500 to "Internal Server Error",
)

/** An error that maps directly onto an HTTP status response. */
class HttpError(val status: Int, val allow: List<String> = emptyList()) :
    RuntimeException(REASONS[status] ?: "Error")

/** Thread-safe in-memory store mapping keys to immutable byte values. */
class KvStore {
    private val map = ConcurrentHashMap<String, ByteArray>()

    operator fun get(key: String): ByteArray? = map[key]

    /** Stores [value]; returns true if the key was newly created. */
    fun put(key: String, value: ByteArray): Boolean = map.put(key, value) == null

    /** Removes [key]; returns true if it was present. */
    fun delete(key: String): Boolean = map.remove(key) != null

    fun sortedKeys(): List<String> = map.keys.sorted()
}

class KvServer(
    private val store: KvStore = KvStore(),
    private val executor: ExecutorService = Executors.newVirtualThreadPerTaskExecutor(),
) {
    private var server: HttpServer? = null

    fun start(host: String, port: Int, backlog: Int = 1024) {
        val http = HttpServer.create(InetSocketAddress(host, port), backlog)
        http.executor = executor
        http.createContext("/") { exchange -> exchange.use(::dispatch) }
        http.start()
        server = http
    }

    fun stop() {
        server?.stop(0)
        executor.shutdownNow()
    }

    private fun dispatch(exchange: HttpExchange) {
        try {
            route(exchange)
        } catch (e: HttpError) {
            if (e.allow.isNotEmpty()) exchange.responseHeaders.set("Allow", e.allow.joinToString(", "))
            if (e.status == 413) exchange.responseHeaders.set("Connection", "close")
            exchange.send(e.status, (e.message ?: "Error").toByteArray())
        } catch (e: Exception) {
            System.err.println("kvhttp: ${e.stackTraceToString()}")
            runCatching { exchange.send(500, REASONS.getValue(500).toByteArray()) }
        }
    }

    private fun route(exchange: HttpExchange) {
        val path = exchange.requestURI.rawPath ?: "/"
        val method = exchange.requestMethod

        when {
            path == "/health" -> {
                requireMethod(method, "GET")
                exchange.send(200, "ok".toByteArray())
            }

            path == "/kv" -> {
                requireMethod(method, "GET")
                val json = store.sortedKeys().joinToString(",", "[", "]") { jsonString(it) }
                exchange.send(200, json.toByteArray(), "application/json")
            }

            path.startsWith("/kv/") -> {
                val key = path.removePrefix("/kv/")
                if (!KEY_RE.matches(key)) throw HttpError(400)
                when (method) {
                    "GET" -> exchange.send(200, store[key] ?: throw HttpError(404), "application/octet-stream")
                    "PUT" -> {
                        val value = exchange.readBody(MAX_VALUE_BYTES)
                        exchange.send(if (store.put(key, value)) 201 else 200)
                    }
                    "DELETE" -> if (store.delete(key)) exchange.send(204) else throw HttpError(404)
                    else -> throw HttpError(405, listOf("GET", "PUT", "DELETE"))
                }
            }

            else -> throw HttpError(404)
        }
    }

    private fun requireMethod(method: String, vararg allowed: String) {
        if (method !in allowed) throw HttpError(405, allowed.toList())
    }
}

/** Sends a complete response; 204 carries neither body nor Content-Length. */
private fun HttpExchange.send(
    status: Int,
    body: ByteArray = ByteArray(0),
    contentType: String = "text/plain; charset=utf-8",
) {
    if (body.isNotEmpty()) responseHeaders.set("Content-Type", contentType)
    when {
        status == 204 -> sendResponseHeaders(status, -1)
        body.isEmpty() -> sendResponseHeaders(status, -1) // emits Content-Length: 0
        else -> {
            sendResponseHeaders(status, body.size.toLong())
            responseBody.write(body)
        }
    }
}

/** Reads the request body, rejecting anything larger than [limit] bytes with 413. */
private fun HttpExchange.readBody(limit: Int): ByteArray {
    val declared = requestHeaders.getFirst("Content-Length")?.trim()?.toLongOrNull()
    if (declared != null && declared > limit) throw HttpError(413)
    return requestBody.use { it.readLimited(limit) }
}

private fun InputStream.readLimited(limit: Int): ByteArray {
    val out = ByteArrayOutputStream()
    val buf = ByteArray(64 * 1024)
    while (true) {
        val n = read(buf)
        if (n < 0) break
        if (out.size() + n > limit) throw HttpError(413)
        out.write(buf, 0, n)
    }
    return out.toByteArray()
}

private fun jsonString(s: String): String = buildString(s.length + 2) {
    append('"')
    for (c in s) {
        when {
            c == '"' -> append("\\\"")
            c == '\\' -> append("\\\\")
            c < ' ' -> append("\\u%04x".format(c.code))
            else -> append(c)
        }
    }
    append('"')
}
