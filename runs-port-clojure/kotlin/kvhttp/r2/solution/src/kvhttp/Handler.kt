package kvhttp

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpHandler
import java.io.InputStream

private val KEY_PATTERN = Regex("[A-Za-z0-9_-]{1,64}")
private const val MAX_VALUE_BYTES = 1024 * 1024
private const val KV_PREFIX = "/kv/"

private class Response(
    val status: Int,
    val body: ByteArray = ByteArray(0),
    val contentType: String? = null,
)

private val METHOD_NOT_ALLOWED = Response(405)
private val NOT_FOUND = Response(404)
private val BAD_REQUEST = Response(400)

/** HTTP handler implementing the kvhttp routes on top of [store]. */
class KvHandler(private val store: Store) : HttpHandler {

    override fun handle(exchange: HttpExchange) {
        exchange.use {
            val response = try {
                route(it)
            } catch (e: Exception) {
                System.err.println("request failed: $e")
                Response(500)
            }
            send(it, response)
        }
    }

    private fun route(exchange: HttpExchange): Response {
        val path = exchange.requestURI.rawPath ?: ""
        val method = exchange.requestMethod
        return when {
            path == "/health" -> health(method)
            path == "/kv" -> listAll(method)
            path.startsWith(KV_PREFIX) -> item(method, path.substring(KV_PREFIX.length), exchange.requestBody)
            else -> NOT_FOUND
        }
    }

    private fun health(method: String): Response =
        if (method == "GET") Response(200, "ok".toByteArray()) else METHOD_NOT_ALLOWED

    private fun listAll(method: String): Response {
        if (method != "GET") return METHOD_NOT_ALLOWED
        // Keys match KEY_PATTERN, so they never need JSON escaping.
        val json = store.keys().joinToString(",", "[", "]") { "\"$it\"" }
        return Response(200, json.toByteArray(), "application/json")
    }

    private fun item(method: String, key: String, body: InputStream): Response {
        if (!KEY_PATTERN.matches(key)) return BAD_REQUEST
        return when (method) {
            "GET" -> store.get(key)?.let { Response(200, it, "application/octet-stream") } ?: NOT_FOUND
            "PUT" -> {
                val value = readLimited(body) ?: return Response(413)
                when (store.put(key, value)) {
                    PutResult.CREATED -> Response(201)
                    PutResult.REPLACED -> Response(200)
                }
            }
            "DELETE" -> if (store.delete(key)) Response(204) else NOT_FOUND
            else -> METHOD_NOT_ALLOWED
        }
    }

    /** Reads the whole body, or returns null if it exceeds [MAX_VALUE_BYTES]. */
    private fun readLimited(body: InputStream): ByteArray? {
        val bytes = body.readNBytes(MAX_VALUE_BYTES + 1)
        return if (bytes.size > MAX_VALUE_BYTES) null else bytes
    }

    private fun send(exchange: HttpExchange, response: Response) {
        response.contentType?.let { exchange.responseHeaders.set("Content-Type", it) }
        exchange.responseHeaders.set("Connection", "close")
        val hasBody = response.body.isNotEmpty() && exchange.requestMethod != "HEAD"
        // A length of -1 tells HttpServer there is no body (Content-Length: 0, or none for 204).
        exchange.sendResponseHeaders(response.status, if (hasBody) response.body.size.toLong() else -1L)
        if (hasBody) exchange.responseBody.write(response.body)
    }
}
