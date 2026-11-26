package kvhttp

import java.io.BufferedOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.concurrent.Executors

private const val MAX_HEADER_BYTES = 16 * 1024
private const val MAX_KEY_LEN = 64
private const val MAX_VALUE_BYTES = 1L shl 20
private const val IO_TIMEOUT_MS = 10_000
private const val DRAIN_LIMIT = 4 * 1024 * 1024
private val HEAD_TERMINATOR = "\r\n\r\n".toByteArray(Charsets.ISO_8859_1)

/**
 * A minimal HTTP/1.1 key-value server: one virtual thread per connection,
 * one request per connection.
 */
class KvServer(private val store: KvStore = KvStore()) {

    fun serve(port: Int) {
        ServerSocket().use { listener ->
            listener.reuseAddress = true
            listener.bind(InetSocketAddress(InetAddress.getLoopbackAddress(), port), 1024)
            Executors.newVirtualThreadPerTaskExecutor().use { executor ->
                while (true) {
                    val socket = try {
                        listener.accept()
                    } catch (e: IOException) {
                        System.err.println("accept: ${e.message}")
                        Thread.sleep(10) // resource pressure: back off briefly
                        continue
                    }
                    executor.execute { handle(socket) }
                }
            }
        }
    }

    private fun handle(socket: Socket) {
        try {
            socket.soTimeout = IO_TIMEOUT_MS
            socket.tcpNoDelay = true
            val input = socket.getInputStream()
            val output = BufferedOutputStream(socket.getOutputStream(), 64 * 1024)
            serveConnection(input, output)
            lingeringClose(socket, input)
        } catch (_: IOException) {
            // Client went away or timed out; nothing more to do.
        } finally {
            socket.close()
        }
    }

    /**
     * Half-closes and drains whatever the peer still sends, so that closing the
     * socket does not reset the connection before the client reads the reply.
     */
    private fun lingeringClose(socket: Socket, input: InputStream) {
        socket.shutdownOutput()
        val sink = ByteArray(4096)
        var total = 0
        while (total < DRAIN_LIMIT) {
            val n = input.read(sink)
            if (n <= 0) break
            total += n
        }
    }

    private fun serveConnection(input: InputStream, output: OutputStream) {
        val buf = ByteArray(MAX_HEADER_BYTES)
        var used = 0
        var headEnd = -1

        while (headEnd < 0) {
            if (used == MAX_HEADER_BYTES) {
                Response.empty(431).writeTo(output)
                return
            }
            val n = try {
                input.read(buf, used, MAX_HEADER_BYTES - used)
            } catch (_: SocketTimeoutException) {
                if (used > 0) Response.empty(408).writeTo(output)
                return
            }
            if (n <= 0) return
            val from = maxOf(used - 3, 0)
            used += n
            headEnd = buf.indexOf(HEAD_TERMINATOR, from, used)
            // Embedded NULs are never valid in a request head.
            val scanEnd = if (headEnd < 0) used else headEnd
            if ((from until scanEnd).any { buf[it] == 0.toByte() }) {
                Response.empty(400).writeTo(output)
                return
            }
        }

        when (val parsed = parseHead(buf, headEnd)) {
            is ParseResult.Error -> Response.empty(parsed.status).writeTo(output)
            is ParseResult.Ok -> {
                val bodyStart = headEnd + HEAD_TERMINATOR.size
                val prefix = buf.copyOfRange(bodyStart, used)
                route(parsed.head, BodyReader(prefix, input))?.writeTo(output)
            }
        }
    }

    /** Returns the response to send, or `null` if the connection should just be closed. */
    private fun route(head: RequestHead, body: BodyReader): Response? {
        val method = head.method
        val target = head.target
        return when {
            target == "/health" ->
                if (method == "GET") Response.text(200, "ok") else Response.methodNotAllowed("GET")

            target == "/kv" ->
                if (method == "GET") listKeys() else Response.methodNotAllowed("GET")

            target.startsWith("/kv/") -> {
                val key = target.substring(4)
                when {
                    !isValidKey(key) -> Response.empty(400)
                    method == "GET" -> getValue(key)
                    method == "PUT" -> putValue(key, head.contentLength, body)
                    method == "DELETE" -> Response.empty(if (store.delete(key)) 204 else 404)
                    else -> Response.methodNotAllowed("GET, PUT, DELETE")
                }
            }

            else -> Response.empty(404)
        }
    }

    private fun listKeys(): Response {
        // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is required.
        val json = store.sortedKeys().joinToString(",", "[", "]") { "\"$it\"" }
        return Response(200, json.toByteArray(Charsets.US_ASCII), contentType = "application/json")
    }

    private fun getValue(key: String): Response {
        val value = store.get(key) ?: return Response.empty(404)
        return Response(200, value, contentType = "application/octet-stream")
    }

    private fun putValue(key: String, contentLength: ULong, body: BodyReader): Response? {
        if (contentLength > MAX_VALUE_BYTES.toULong()) return Response.empty(413)
        val value = body.readExactly(contentLength.toInt()) ?: return null
        return Response.empty(if (store.put(key, value)) 201 else 200)
    }
}

/** Reads a request body, starting with bytes that arrived together with the head. */
private class BodyReader(private val prefix: ByteArray, private val input: InputStream) {
    /** Reads exactly [len] bytes; returns `null` on EOF before that. */
    fun readExactly(len: Int): ByteArray? {
        val data = ByteArray(len)
        val have = minOf(prefix.size, len)
        prefix.copyInto(data, endIndex = have)
        return if (input.readNBytes(data, have, len - have) == len - have) data else null
    }
}

fun isValidKey(key: String): Boolean =
    key.length in 1..MAX_KEY_LEN &&
        key.all { it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it == '_' || it == '-' }

private fun ByteArray.indexOf(needle: ByteArray, from: Int, to: Int): Int {
    outer@ for (i in from..to - needle.size) {
        for (j in needle.indices) if (this[i + j] != needle[j]) continue@outer
        return i
    }
    return -1
}
