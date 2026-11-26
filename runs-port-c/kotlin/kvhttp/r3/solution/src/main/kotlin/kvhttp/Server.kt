// HTTP server: one virtual thread per connection, one request per connection.
package kvhttp

import java.io.IOException
import java.io.InputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.max
import kotlin.math.min

class Server(private val port: Int, private val router: Router) {

    /** Binds 127.0.0.1:[port] and serves forever. Throws [IOException] if the port cannot be bound. */
    fun run() {
        ServerSocket().use { listener ->
            listener.reuseAddress = true
            listener.bind(InetSocketAddress(InetAddress.getLoopbackAddress(), port), BACKLOG)
            Executors.newVirtualThreadPerTaskExecutor().use { executor ->
                while (!listener.isClosed) {
                    val socket = try {
                        listener.accept()
                    } catch (e: IOException) {
                        if (listener.isClosed) break
                        System.err.println("kvhttp: accept: ${e.message}")
                        continue
                    }
                    executor.execute { Connection(socket, router).serve() }
                }
            }
        }
    }

    private companion object {
        const val BACKLOG = 4096
    }
}

/** Serves exactly one request on [socket], then closes it. */
private class Connection(private val socket: Socket, private val router: Router) {
    /** Overall budget for receiving the request and sending the response. */
    private var deadline = System.nanoTime() + IO_TIMEOUT_NANOS

    fun serve() {
        socket.use {
            try {
                it.tcpNoDelay = true
                val response = readRequest(it.getInputStream()) ?: return
                send(response)
                drain(it.getInputStream())
            } catch (_: IOException) {
                // Peer went away or the connection timed out; nothing more to do.
            }
        }
    }

    /** Reads one request and produces its response, or returns null if the client left early. */
    private fun readRequest(input: InputStream): Response? {
        val buf = ByteArray(MAX_HEAD)
        var len = 0
        var headLen = 0
        while (headLen == 0) {
            if (len == MAX_HEAD) return Response(431)
            val n = read(input, buf, len, MAX_HEAD - len)
            if (n < 0) return null
            val scanFrom = max(0, len - 2)
            len += n
            headLen = Http.headLength(buf, len, scanFrom)
        }

        val head = when (val parsed = Http.parseHead(buf, headLen)) {
            is HeadParse.Ok -> parsed.head
            is HeadParse.Invalid -> return Response(parsed.status)
        }
        if (head.contentLength > MAX_VALUE_LENGTH.toULong()) return Response(413)

        val body = ByteArray(head.contentLength.toInt())
        var filled = min(len - headLen, body.size)
        buf.copyInto(body, 0, headLen, headLen + filled)
        if (head.expectContinue && filled < body.size) {
            socket.getOutputStream().apply { write(Http.CONTINUE_LINE); flush() }
        }
        while (filled < body.size) {
            val n = read(input, body, filled, body.size - filled)
            if (n < 0) return null
            filled += n
        }
        return router.route(head, body)
    }

    private fun send(response: Response) {
        socket.getOutputStream().apply {
            write(response.encodeHead())
            write(response.encodedBody())
            flush()
        }
    }

    /**
     * Half-closes and discards whatever the client still sends, so that unread request bytes do not
     * trigger a RST that could discard the response.
     */
    private fun drain(input: InputStream) {
        socket.shutdownOutput()
        deadline = System.nanoTime() + DRAIN_TIMEOUT_NANOS
        val scratch = ByteArray(DRAIN_CHUNK)
        while (read(input, scratch, 0, scratch.size) >= 0) {
            // discard
        }
    }

    /** A read bounded by the connection deadline. */
    private fun read(input: InputStream, into: ByteArray, off: Int, len: Int): Int {
        val remainingMillis = TimeUnit.NANOSECONDS.toMillis(deadline - System.nanoTime())
        if (remainingMillis <= 0) throw SocketTimeoutException("connection deadline passed")
        socket.soTimeout = remainingMillis.toInt()
        return input.read(into, off, len)
    }

    private companion object {
        const val MAX_HEAD = 64 * 1024
        const val DRAIN_CHUNK = 16 * 1024
        val IO_TIMEOUT_NANOS = TimeUnit.SECONDS.toNanos(30)
        val DRAIN_TIMEOUT_NANOS = TimeUnit.SECONDS.toNanos(2)
    }
}
