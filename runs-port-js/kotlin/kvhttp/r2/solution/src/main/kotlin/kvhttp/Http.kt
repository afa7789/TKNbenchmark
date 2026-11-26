package kvhttp

import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

private const val MAX_HEADER_BYTES = 64 * 1024
private const val SOCKET_TIMEOUT_MS = 30_000

class Request(
    val method: String,
    val target: String,
    val headers: Map<String, String>,
    private val bodyReader: (limit: Int) -> ByteArray,
) {
    fun header(name: String): String? = headers[name.lowercase()]

    /** Reads the whole body; throws [HttpError] 413 if it exceeds [limit] bytes. */
    fun body(limit: Int): ByteArray = bodyReader(limit)
}

class Response(
    val status: Int,
    val body: ByteArray = ByteArray(0),
    val headers: Map<String, String> = emptyMap(),
)

/** Signals that a request should be answered with [status] and an empty body. */
class HttpError(val status: Int) : Exception("HTTP $status", null, false, false)

/** Thrown when the bytes on the wire are not a valid HTTP/1.1 request. */
private class MalformedRequest(message: String) : IOException(message)

fun interface Handler {
    fun handle(request: Request): Response
}

/**
 * A minimal HTTP/1.1 server: one virtual thread per connection, persistent connections,
 * Content-Length and chunked request bodies.
 */
class HttpServer(private val handler: Handler) : AutoCloseable {
    private val executor: ExecutorService = Executors.newVirtualThreadPerTaskExecutor()
    private var serverSocket: ServerSocket? = null

    fun start(host: String, port: Int) {
        val socket = ServerSocket().apply {
            reuseAddress = true
            bind(InetSocketAddress(InetAddress.getByName(host), port), 1024)
        }
        serverSocket = socket
        Thread.ofPlatform().name("http-acceptor").start {
            while (!socket.isClosed) {
                val client = try {
                    socket.accept()
                } catch (e: IOException) {
                    if (socket.isClosed) break else continue
                }
                executor.execute { serve(client) }
            }
        }
    }

    override fun close() {
        serverSocket?.close()
        executor.shutdownNow()
    }

    private fun serve(socket: Socket) {
        socket.use {
            try {
                it.soTimeout = SOCKET_TIMEOUT_MS
                it.tcpNoDelay = true
                val input = BufferedInputStream(it.getInputStream(), 16 * 1024)
                val output = BufferedOutputStream(it.getOutputStream(), 16 * 1024)
                while (serveOne(input, output)) Unit
            } catch (_: MalformedRequest) {
                runCatching { writeRaw(it.getOutputStream(), Response(400, headers = mapOf("Connection" to "close")), false) }
            } catch (_: IOException) {
                // Client went away or timed out; nothing to answer.
            }
        }
    }

    /** Serves one request; returns whether the connection may be reused. */
    private fun serveOne(input: InputStream, output: OutputStream): Boolean {
        val head = readHead(input) ?: return false
        val lines = head.split("\r\n")
        val parts = lines[0].split(' ')
        if (parts.size != 3 || parts[0].isEmpty() || parts[1].isEmpty() || !parts[2].startsWith("HTTP/1.")) {
            throw MalformedRequest("bad request line")
        }
        val (method, target, version) = parts
        val headers = HashMap<String, String>()
        for (line in lines.drop(1)) {
            val colon = line.indexOf(':')
            if (colon <= 0) throw MalformedRequest("bad header line")
            val name = line.substring(0, colon).trim().lowercase()
            val value = line.substring(colon + 1).trim()
            headers.merge(name, value) { a, b -> "$a, $b" }
        }

        val chunked = headers["transfer-encoding"]?.lowercase()?.contains("chunked") == true
        val contentLength = when {
            chunked -> null
            else -> headers["content-length"]?.let { it.toLongOrNull()?.takeIf { n -> n >= 0 } ?: throw MalformedRequest("bad length") }
        } ?: 0L
        val body = BodyReader(input, output, chunked, contentLength, headers["expect"].equals("100-continue", true))

        val request = Request(method, target, headers) { limit -> body.readAll(limit) }
        val response = try {
            handler.handle(request)
        } catch (e: HttpError) {
            Response(e.status)
        } catch (e: IOException) {
            throw e
        } catch (e: Exception) {
            System.err.println("internal error: $e")
            Response(500)
        }

        var keepAlive = version == "HTTP/1.1" && !headers["connection"].equals("close", true) && response.status < 400
        // Skip any body the handler left unread so the next request starts at the right byte.
        if (keepAlive) keepAlive = body.drain()
        writeRaw(output, response, keepAlive)
        return keepAlive
    }

    private fun readHead(input: InputStream): String? {
        val buf = ByteArrayOutputStream(512)
        var matched = 0
        while (true) {
            val b = input.read()
            if (b < 0) {
                if (buf.size() == 0) return null
                throw MalformedRequest("truncated head")
            }
            // Tolerate stray CRLFs between requests.
            if (buf.size() == 0 && (b == '\r'.code || b == '\n'.code)) continue
            buf.write(b)
            matched = when {
                b == '\r'.code && (matched == 0 || matched == 2) -> matched + 1
                b == '\n'.code && (matched == 1 || matched == 3) -> matched + 1
                else -> 0
            }
            if (matched == 4) break
            if (buf.size() > MAX_HEADER_BYTES) throw MalformedRequest("head too large")
        }
        val bytes = buf.toByteArray()
        return String(bytes, 0, bytes.size - 4, Charsets.ISO_8859_1)
    }

    private fun writeRaw(output: OutputStream, response: Response, keepAlive: Boolean) {
        val noBody = response.status == 204 || response.status == 304
        val head = buildString {
            append("HTTP/1.1 ").append(response.status).append(' ').append(reasonPhrase(response.status)).append("\r\n")
            for ((name, value) in response.headers) if (!name.equals("Connection", true)) append(name).append(": ").append(value).append("\r\n")
            if (!noBody) append("Content-Length: ").append(response.body.size).append("\r\n")
            append("Connection: ").append(if (keepAlive) "keep-alive" else "close").append("\r\n\r\n")
        }
        output.write(head.toByteArray(Charsets.ISO_8859_1))
        if (!noBody) output.write(response.body)
        output.flush()
    }
}

/** Streams a request body, enforcing size limits and answering `Expect: 100-continue`. */
private class BodyReader(
    private val input: InputStream,
    private val output: OutputStream,
    private val chunked: Boolean,
    private var remaining: Long,
    private var expectContinue: Boolean,
) {
    private var consumed = false

    fun readAll(limit: Int): ByteArray {
        check(!consumed) { "body already read" }
        if (!chunked && remaining > limit) throw HttpError(413)
        sendContinue()
        consumed = true
        return if (chunked) readChunked(limit) else readFixed(remaining.toInt())
    }

    /** Discards an unread body; returns false if that is not worth doing (connection should close). */
    fun drain(): Boolean {
        if (consumed) return true
        if (expectContinue) return chunked.not() && remaining == 0L
        consumed = true
        if (chunked) return false
        if (remaining > 1024 * 1024) return false
        input.skipNBytes(remaining)
        return true
    }

    private fun sendContinue() {
        if (expectContinue) {
            output.write("HTTP/1.1 100 Continue\r\n\r\n".toByteArray(Charsets.ISO_8859_1))
            output.flush()
            expectContinue = false
        }
    }

    private fun readFixed(n: Int): ByteArray {
        val bytes = input.readNBytes(n)
        if (bytes.size < n) throw EOFException("truncated body")
        return bytes
    }

    private fun readChunked(limit: Int): ByteArray {
        val out = ByteArrayOutputStream()
        while (true) {
            val sizeLine = readLine().substringBefore(';').trim()
            val size = sizeLine.toIntOrNull(16)?.takeIf { it >= 0 } ?: throw MalformedRequest("bad chunk size")
            if (size == 0) break
            if (out.size().toLong() + size > limit) throw HttpError(413)
            out.write(readFixed(size))
            if (readLine().isNotEmpty()) throw MalformedRequest("bad chunk terminator")
        }
        while (readLine().isNotEmpty()) Unit // trailers
        return out.toByteArray()
    }

    private fun readLine(): String {
        val sb = StringBuilder()
        while (true) {
            val b = input.read()
            if (b < 0) throw EOFException("truncated chunked body")
            if (b == '\n'.code) return sb.toString().removeSuffix("\r")
            sb.append(b.toChar())
            if (sb.length > 4096) throw MalformedRequest("line too long")
        }
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
    else -> "Unknown"
}
