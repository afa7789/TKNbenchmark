package kvhttp

import java.io.BufferedOutputStream
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors

/** Largest accepted value (request body), in bytes. */
const val MAX_VALUE_BYTES = 1024 * 1024

private const val IO_TIMEOUT_MS = 30_000
private const val LINGER_TIMEOUT_MS = 500
private const val LINGER_DRAIN_LIMIT = 4L * MAX_VALUE_BYTES
private const val ACCEPT_BACKOFF_MS = 10L
private const val BACKLOG = 1024

/** Serves one request per connection, each on its own virtual thread. */
class Server(private val port: Int, private val router: Router) {

    /** Binds to the loopback interface and serves until the process is killed. */
    fun serve() {
        val listener = ServerSocket().apply {
            reuseAddress = true
            bind(InetSocketAddress(InetAddress.getLoopbackAddress(), port), BACKLOG)
        }
        listener.use {
            Executors.newVirtualThreadPerTaskExecutor().use { executor ->
                while (!listener.isClosed) {
                    val socket = try {
                        listener.accept()
                    } catch (e: IOException) {
                        if (listener.isClosed) break
                        // Typically resource exhaustion: back off briefly instead of spinning.
                        System.err.println("accept: ${e.message}")
                        Thread.sleep(ACCEPT_BACKOFF_MS)
                        continue
                    }
                    executor.execute { handleConnection(socket) }
                }
            }
        }
    }

    private fun handleConnection(socket: Socket) {
        try {
            socket.soTimeout = IO_TIMEOUT_MS
            socket.tcpNoDelay = true
            val output = BufferedOutputStream(socket.getOutputStream())
            val response = try {
                router.route(readRequest(socket.getInputStream(), output, MAX_VALUE_BYTES))
            } catch (e: HttpException) {
                HttpResponse(e.status)
            }
            writeResponse(output, response)
            socket.lingeringClose()
        } catch (_: IOException) {
            // The peer went away or timed out; there is nobody left to answer.
            socket.closeQuietly()
        }
    }
}

/**
 * Half-closes and drains the socket so unread request bytes do not turn the close
 * into a RST that could destroy the response before the client reads it.
 */
private fun Socket.lingeringClose() {
    try {
        shutdownOutput()
        soTimeout = LINGER_TIMEOUT_MS
        val input = getInputStream()
        val sink = ByteArray(4096)
        var total = 0L
        while (total < LINGER_DRAIN_LIMIT) {
            val n = input.read(sink)
            if (n <= 0) break
            total += n
        }
    } catch (_: IOException) {
        // Draining is best effort.
    } finally {
        closeQuietly()
    }
}

private fun Socket.closeQuietly() {
    try {
        close()
    } catch (_: IOException) {
    }
}
