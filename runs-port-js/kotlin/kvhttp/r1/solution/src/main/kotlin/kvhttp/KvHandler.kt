package kvhttp

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpHandler
import java.io.IOException
import java.io.InputStream

const val MAX_VALUE_BYTES = 1024 * 1024

private val KEY_REGEX = Regex("[A-Za-z0-9_-]{1,64}")
private const val KV_PREFIX = "/kv/"

private const val TEXT_PLAIN = "text/plain; charset=utf-8"
private const val APPLICATION_JSON = "application/json"
private const val OCTET_STREAM = "application/octet-stream"

/** An error that maps directly to an HTTP status response. */
class HttpError(val status: Int, val allow: List<String> = emptyList()) : Exception(reasonPhrase(status))

private class Response(
    val status: Int,
    val body: ByteArray = ByteArray(0),
    val contentType: String? = null,
    val headers: Map<String, String> = emptyMap(),
)

class KvHandler(private val store: KvStore) : HttpHandler {

    override fun handle(exchange: HttpExchange) {
        exchange.use {
            val response = try {
                route(exchange)
            } catch (e: HttpError) {
                errorResponse(e)
            } catch (e: IOException) {
                throw e
            } catch (e: Exception) {
                System.err.println("internal error: $e")
                errorResponse(HttpError(500))
            }
            send(exchange, response)
        }
    }

    private fun route(exchange: HttpExchange): Response {
        // Always drain the body first so error responses don't reset the connection.
        val body = readBody(exchange)
        val method = exchange.requestMethod
        val path = exchange.requestURI.rawPath ?: "/"

        return when {
            path == "/health" -> health(method)
            path == "/kv" -> list(method)
            path.startsWith(KV_PREFIX) -> {
                val key = path.substring(KV_PREFIX.length)
                if (!KEY_REGEX.matches(key)) throw HttpError(400)
                item(method, key, body)
            }
            else -> throw HttpError(404)
        }
    }

    private fun health(method: String): Response {
        requireMethod(method, "GET")
        return Response(200, "ok".toByteArray(), TEXT_PLAIN)
    }

    private fun list(method: String): Response {
        requireMethod(method, "GET")
        return Response(200, toJsonArray(store.sortedKeys()).toByteArray(), APPLICATION_JSON)
    }

    private fun item(method: String, key: String, body: ByteArray): Response = when (method) {
        "GET" -> Response(200, store[key] ?: throw HttpError(404), OCTET_STREAM)
        "PUT" -> Response(if (store.put(key, body)) 201 else 200)
        "DELETE" -> if (store.remove(key)) Response(204) else throw HttpError(404)
        else -> throw HttpError(405, listOf("GET", "PUT", "DELETE"))
    }

    private fun requireMethod(method: String, vararg allowed: String) {
        if (method !in allowed) throw HttpError(405, allowed.toList())
    }

    private fun errorResponse(e: HttpError): Response {
        val headers = buildMap {
            if (e.allow.isNotEmpty()) put("Allow", e.allow.joinToString(", "))
            if (e.status == 413) put("Connection", "close")
        }
        return Response(e.status, reasonPhrase(e.status).toByteArray(), TEXT_PLAIN, headers)
    }

    private fun send(exchange: HttpExchange, response: Response) {
        val headers = exchange.responseHeaders
        response.contentType?.let { headers.set("Content-Type", it) }
        response.headers.forEach { (name, value) -> headers.set(name, value) }

        val noBody = response.status == 204 || response.body.isEmpty() || exchange.requestMethod == "HEAD"
        if (noBody) {
            // -1 means "no body": the server emits Content-Length: 0 (omitted for 204).
            exchange.sendResponseHeaders(response.status, -1)
        } else {
            exchange.sendResponseHeaders(response.status, response.body.size.toLong())
            exchange.responseBody.write(response.body)
        }
    }

    private fun readBody(exchange: HttpExchange): ByteArray {
        val declared = exchange.requestHeaders.getFirst("Content-Length")?.trim()?.toLongOrNull() ?: 0L
        if (declared > MAX_VALUE_BYTES) throw HttpError(413)
        return exchange.requestBody.readCapped(MAX_VALUE_BYTES)
    }
}

/** Reads the whole stream, failing with 413 if it holds more than [limit] bytes. */
private fun InputStream.readCapped(limit: Int): ByteArray {
    val bytes = readNBytes(limit)
    if (read() != -1) throw HttpError(413)
    return bytes
}

/** Keys are restricted to `[A-Za-z0-9_-]`, but escape defensively anyway. */
private fun toJsonArray(items: List<String>): String =
    items.joinToString(",", "[", "]") { s ->
        buildString {
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
    }

private fun reasonPhrase(status: Int): String = when (status) {
    200 -> "OK"
    201 -> "Created"
    204 -> "No Content"
    400 -> "Bad Request"
    404 -> "Not Found"
    405 -> "Method Not Allowed"
    413 -> "Payload Too Large"
    500 -> "Internal Server Error"
    else -> status.toString()
}
