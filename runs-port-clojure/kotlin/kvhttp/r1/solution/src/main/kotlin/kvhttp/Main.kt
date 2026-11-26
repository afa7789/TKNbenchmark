package kvhttp

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.util.concurrent.Executors
import kotlin.system.exitProcess

/** Largest accepted request body: 1 MiB values plus generous headroom. */
private const val MAX_BODY = 8 * 1024 * 1024

private const val BACKLOG = 1024

private fun parsePort(s: String?): Int? = s?.toIntOrNull()?.takeIf { it in 1..65535 }

private fun readBody(exchange: HttpExchange): ByteArray {
    val declared = exchange.requestHeaders.getFirst("Content-Length")?.trim()?.toLongOrNull()
    if (declared != null && declared > MAX_BODY) throw PayloadTooLarge()
    val bytes = exchange.requestBody.readNBytes(MAX_BODY + 1)
    if (bytes.size > MAX_BODY) throw PayloadTooLarge()
    return bytes
}

private class PayloadTooLarge : RuntimeException(null, null, false, false)

private fun serve(handler: Handler, exchange: HttpExchange) {
    exchange.use {
        val request = Request(exchange.requestMethod, exchange.requestURI.rawPath) { readBody(exchange) }
        val response = try {
            handler.handle(request)
        } catch (_: PayloadTooLarge) {
            Response(413)
        }
        response.headers.forEach { (name, value) -> exchange.responseHeaders.set(name, value) }
        // -1 tells HttpServer to send `Content-Length: 0` with no body.
        val length = if (response.body.isEmpty()) -1L else response.body.size.toLong()
        exchange.sendResponseHeaders(response.status, length)
        if (response.body.isNotEmpty()) exchange.responseBody.write(response.body)
    }
}

fun main(args: Array<String>) {
    val port = parsePort(args.firstOrNull()) ?: run {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }
    val handler = Handler(Store())
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", port), BACKLOG)
    server.executor = Executors.newVirtualThreadPerTaskExecutor()
    server.createContext("/") { exchange -> serve(handler, exchange) }
    server.start()
    println("kvhttp listening on 127.0.0.1:$port")
}
