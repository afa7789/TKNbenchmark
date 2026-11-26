package kvhttp

import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.nio.charset.StandardCharsets
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

data class ServerOptions(
    val port: Int = 8080,
    val maxHeadBytes: Int = 64 * 1024,
    val maxBodyBytes: Int = 1024 * 1024,
    val ioTimeout: Duration = 10.seconds,
)

typealias Handler = (Request) -> Response

/**
 * Minimal HTTP/1.1 server: one request per connection, one virtual thread per
 * connection. Listens on 127.0.0.1.
 */
class Server(private val options: ServerOptions, private val handler: Handler) : AutoCloseable {
    private var serverSocket: ServerSocket? = null
    private val executor: ExecutorService = Executors.newVirtualThreadPerTaskExecutor()

    /** Binds and listens; throws [IOException] on failure. */
    fun listen() {
        serverSocket = ServerSocket().apply {
            reuseAddress = true
            bind(InetSocketAddress(InetAddress.getLoopbackAddress(), options.port), BACKLOG)
        }
    }

    /** Accept loop; does not return under normal operation. */
    fun run(): Nothing {
        val listener = checkNotNull(serverSocket) { "listen() must be called before run()" }
        while (true) {
            val socket = try {
                listener.accept()
            } catch (e: IOException) {
                System.err.println("accept: ${e.message}")
                Thread.sleep(10)
                continue
            }
            executor.execute { handleConnection(socket) }
        }
    }

    override fun close() {
        serverSocket?.close()
        executor.shutdownNow()
    }

    private fun handleConnection(socket: Socket): Unit = socket.use {
        try {
            socket.soTimeout = options.ioTimeout.inWholeMilliseconds.toInt()
            socket.tcpNoDelay = true
            val conn = Connection(socket, options)

            val request = try {
                conn.readRequest()
            } catch (e: HttpError) {
                conn.sendResponse(Response.text(e.status, reasonPhrase(e.status)), includeBody = true)
                conn.lingerClose()
                return
            }

            val response = try {
                handler(request)
            } catch (e: Exception) {
                System.err.println("handler error: $e")
                Response.text(500, "Internal Server Error")
            }
            conn.sendResponse(response, includeBody = request.method != "HEAD")
            conn.lingerClose()
        } catch (_: ConnectionClosed) {
            // Peer went away; nothing more to do.
        } catch (_: IOException) {
            // Peer went away; nothing more to do.
        }
    }

    private companion object {
        const val BACKLOG = 1024
    }
}

/** Thrown when the peer misbehaves in a way that should produce an HTTP error. */
private class HttpError(val status: Int) : Exception(null, null, false, false)

/** Thrown when the connection is unusable (peer closed, timeout, I/O error). */
private class ConnectionClosed : Exception(null, null, false, false)

/** Growable byte buffer that is consumed from the front. */
private class InputBuffer {
    private var data = ByteArray(16 * 1024)
    private var start = 0
    private var end = 0

    val size get() = end - start

    fun indexOf(pattern: ByteArray, from: Int = 0): Int {
        val last = end - pattern.size
        var i = start + from
        outer@ while (i <= last) {
            for (j in pattern.indices) {
                if (data[i + j] != pattern[j]) {
                    i++
                    continue@outer
                }
            }
            return i - start
        }
        return -1
    }

    fun readFrom(input: InputStream): Int {
        if (end == data.size) {
            if (start > 0) {
                data.copyInto(data, 0, start, end)
                end -= start
                start = 0
            }
            if (end == data.size) data = data.copyOf(data.size * 2)
        }
        val n = input.read(data, end, data.size - end)
        if (n > 0) end += n
        return n
    }

    fun take(n: Int): ByteArray {
        require(n <= size)
        val out = data.copyOfRange(start, start + n)
        start += n
        return out
    }

    fun takeString(n: Int): String = String(take(n), StandardCharsets.ISO_8859_1)

    fun skip(n: Int) {
        require(n <= size)
        start += n
    }
}

private val CRLF_BYTES = "\r\n".toByteArray(StandardCharsets.ISO_8859_1)
private val HEAD_END_BYTES = "\r\n\r\n".toByteArray(StandardCharsets.ISO_8859_1)

private class Connection(private val socket: Socket, private val options: ServerOptions) {
    private val input: InputStream = socket.getInputStream()
    private val output: OutputStream = socket.getOutputStream()
    private val buffer = InputBuffer()

    fun readRequest(): Request {
        var headEnd: Int
        while (buffer.indexOf(HEAD_END_BYTES).also { headEnd = it } < 0) {
            if (buffer.size > options.maxHeadBytes) throw HttpError(431)
            if (!fill()) throw ConnectionClosed()
        }
        val head = parseHead(buffer.takeString(headEnd)) ?: throw HttpError(400)
        buffer.skip(HEAD_END_BYTES.size)
        return head.withBody(readBody(head))
    }

    fun sendResponse(response: Response, includeBody: Boolean) {
        output.write(response.serializeHead())
        if (includeBody) output.write(response.body)
        output.flush()
    }

    /**
     * Half-closes the socket and discards any remaining input so the client
     * sees the response rather than a reset.
     */
    fun lingerClose() {
        try {
            socket.shutdownOutput()
            socket.soTimeout = 1000
            val scratch = ByteArray(16 * 1024)
            var drained = 0L
            while (drained < MAX_DRAIN) {
                val n = input.read(scratch)
                if (n <= 0) break
                drained += n
            }
        } catch (_: IOException) {
            // Best effort only.
        }
    }

    /** Reads more bytes into the buffer; returns false on EOF. */
    private fun fill(): Boolean = try {
        buffer.readFrom(input) > 0
    } catch (_: SocketTimeoutException) {
        throw HttpError(408)
    } catch (_: IOException) {
        throw ConnectionClosed()
    }

    /** Ensures at least [n] bytes are buffered. */
    private fun require(n: Int) {
        while (buffer.size < n) {
            if (!fill()) throw HttpError(400)
        }
    }

    private fun take(n: Int): ByteArray {
        require(n)
        return buffer.take(n)
    }

    private fun readLine(): String {
        var pos: Int
        while (buffer.indexOf(CRLF_BYTES).also { pos = it } < 0) {
            if (buffer.size > options.maxHeadBytes) throw HttpError(400)
            if (!fill()) throw HttpError(400)
        }
        val line = buffer.takeString(pos)
        buffer.skip(CRLF_BYTES.size)
        return line
    }

    private fun readBody(request: Request): ByteArray {
        request.header("Transfer-Encoding")?.let { te ->
            if (!te.equals("chunked", ignoreCase = true)) throw HttpError(501)
            return readChunkedBody()
        }
        val lengthHeader = request.header("Content-Length") ?: return ByteArray(0)
        if (lengthHeader.isEmpty() || !lengthHeader.all { it in '0'..'9' }) throw HttpError(400)
        val length = lengthHeader.toLongOrNull() ?: throw HttpError(413)
        if (length > options.maxBodyBytes) throw HttpError(413)
        return take(length.toInt())
    }

    private fun readChunkedBody(): ByteArray {
        val body = java.io.ByteArrayOutputStream()
        while (true) {
            val sizeText = readLine().substringBefore(';')
            if (sizeText.isEmpty() || !sizeText.all { it.isHexDigit() }) throw HttpError(400)
            val size = sizeText.toLongOrNull(16) ?: throw HttpError(413)
            if (size == 0L) {
                // Discard trailer fields up to the terminating blank line.
                while (readLine().isNotEmpty()) continue
                return body.toByteArray()
            }
            if (size > options.maxBodyBytes - body.size()) throw HttpError(413)
            body.write(take(size.toInt()))
            if (readLine().isNotEmpty()) throw HttpError(400)
        }
    }

    private fun Char.isHexDigit() = this in '0'..'9' || this in 'a'..'f' || this in 'A'..'F'

    private companion object {
        const val MAX_DRAIN = 16L * 1024 * 1024
    }
}
