package kvhttp

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.io.InputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.Executors
import kotlin.system.exitProcess

const val MAX_VALUE_BYTES = 1 shl 20

fun main(args: Array<String>) {
    val port = args.singleOrNull()?.toIntOrNull()?.takeIf { it in 1..65535 } ?: run {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }
    val router = Router(KvStore())
    val server = HttpServer.create(InetSocketAddress(InetAddress.getLoopbackAddress(), port), 1024)
    server.executor = Executors.newVirtualThreadPerTaskExecutor()
    server.createContext("/") { exchange -> exchange.use { serve(it, router) } }
    server.start()
}

private fun serve(exchange: HttpExchange, router: Router) {
    val response = try {
        val body = readBody(exchange)
        if (body == null) {
            Response.text(413, "value too large")
        } else {
            router.handle(exchange.requestMethod, exchange.requestURI.rawPath, body)
        }
    } catch (e: Exception) {
        System.err.println("request failed: $e")
        Response.text(500, "internal error")
    }
    send(exchange, response)
}

/** Reads the request body, or returns `null` if it exceeds [MAX_VALUE_BYTES]. */
private fun readBody(exchange: HttpExchange): ByteArray? {
    val declared = exchange.requestHeaders.getFirst("Content-Length")?.trim()?.toLongOrNull()
    if (declared != null && declared > MAX_VALUE_BYTES) return null
    return exchange.requestBody.use { it.readAtMost(MAX_VALUE_BYTES) }
}

private fun InputStream.readAtMost(limit: Int): ByteArray? {
    val bytes = readNBytes(limit)
    return if (read() == -1) bytes else null
}

private fun send(exchange: HttpExchange, response: Response) {
    response.contentType?.let { exchange.responseHeaders["Content-Type"] = it }
    val body = response.body
    // A length of -1 tells HttpServer there is no body; it then emits Content-Length: 0 (none for 204).
    val length = if (body.isEmpty()) -1L else body.size.toLong()
    exchange.sendResponseHeaders(response.status, length)
    if (body.isNotEmpty()) exchange.responseBody.use { it.write(body) }
}
