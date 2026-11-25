package kvhttp

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpHandler

const val MAX_VALUE_BYTES = 1 shl 20

private val KEY_PATTERN = Regex("[A-Za-z0-9_-]{1,64}")

private class HttpError(val status: Int) : Exception(null, null, false, false)

/** Routes requests for the kvhttp API. */
class KvHandler(private val store: KvStore) : HttpHandler {

    override fun handle(exchange: HttpExchange) {
        exchange.use {
            try {
                route(it)
            } catch (e: HttpError) {
                it.respond(e.status)
            }
        }
    }

    private fun route(ex: HttpExchange) {
        val path = ex.requestURI.rawPath ?: ""
        when {
            path == "/health" -> {
                ex.requireMethod("GET")
                ex.respond(200, "ok".toByteArray(), "text/plain; charset=utf-8")
            }
            path == "/kv" -> {
                ex.requireMethod("GET")
                val json = store.sortedKeys().joinToString(",", "[", "]") { "\"$it\"" }
                ex.respond(200, json.toByteArray(), "application/json")
            }
            path.startsWith("/kv/") -> handleKey(ex, path.removePrefix("/kv/"))
            else -> throw HttpError(404)
        }
    }

    private fun handleKey(ex: HttpExchange, key: String) {
        ex.requireMethod("GET", "PUT", "DELETE")
        if (!KEY_PATTERN.matches(key)) throw HttpError(400)
        when (ex.requestMethod) {
            "GET" -> {
                val value = store[key] ?: throw HttpError(404)
                ex.respond(200, value, "application/octet-stream")
            }
            "PUT" -> {
                val value = ex.readBody()
                ex.respond(if (store.put(key, value)) 201 else 200)
            }
            "DELETE" -> ex.respond(if (store.delete(key)) 204 else 404)
        }
    }
}

private fun HttpExchange.requireMethod(vararg allowed: String) {
    if (requestMethod !in allowed) {
        responseHeaders.set("Allow", allowed.joinToString(", "))
        throw HttpError(405)
    }
}

private fun HttpExchange.readBody(): ByteArray {
    val declared = requestHeaders.getFirst("Content-Length")?.trim()?.toLongOrNull()
    if (declared != null && declared > MAX_VALUE_BYTES) throw HttpError(413)
    val body = requestBody.readNBytes(MAX_VALUE_BYTES + 1)
    if (body.size > MAX_VALUE_BYTES) throw HttpError(413)
    return body
}

private fun HttpExchange.respond(status: Int, body: ByteArray = ByteArray(0), contentType: String? = null) {
    contentType?.let { responseHeaders.set("Content-Type", it) }
    if (body.isEmpty()) {
        // -1 means "no body": the JDK server emits Content-Length: 0 (omitted for 204).
        sendResponseHeaders(status, -1)
    } else {
        sendResponseHeaders(status, body.size.toLong())
        responseBody.write(body)
    }
}
