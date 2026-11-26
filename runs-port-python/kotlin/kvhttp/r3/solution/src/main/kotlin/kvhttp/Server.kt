package kvhttp

import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.concurrent.Executors
import java.util.logging.Level
import java.util.logging.Logger
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource

private val log: Logger = Logger.getLogger("kvhttp")

/**
 * Blocking HTTP/1.1 server running each connection on a virtual thread.
 * Serves exactly one request per connection, then closes it.
 */
class Server(
    private val app: App,
    private val readTimeout: Duration = 30.seconds,
) {
    fun serve(host: String, port: Int) {
        ServerSocket().use { listener ->
            listener.reuseAddress = true
            listener.bind(InetSocketAddress(InetAddress.getByName(host), port), BACKLOG)
            Executors.newVirtualThreadPerTaskExecutor().use { executor ->
                while (true) {
                    val socket = listener.accept()
                    executor.execute { handleConnection(socket) }
                }
            }
        }
    }

    private fun handleConnection(socket: Socket) {
        socket.use {
            try {
                val response = try {
                    app.handle(RequestReader(DeadlineInputStream(socket, readTimeout)).readRequest())
                } catch (e: HttpException) {
                    Response(e.status)
                }
                socket.getOutputStream().apply {
                    write(response.encode())
                    flush()
                }
                socket.shutdownOutput()
            } catch (_: EOFException) {
                // Client went away mid-request; nothing useful to send.
            } catch (_: SocketTimeoutException) {
                // Client stalled past the read deadline.
            } catch (_: IOException) {
                // Connection reset or similar transport failure.
            } catch (e: Exception) {
                log.log(Level.WARNING, "unhandled error while serving request", e)
            }
        }
    }

    private companion object {
        const val BACKLOG = 1024
    }
}

/** Enforces a total deadline across all reads of a socket, not just per read call. */
private class DeadlineInputStream(private val socket: Socket, timeout: Duration) : InputStream() {
    private val deadline = TimeSource.Monotonic.markNow() + timeout
    private val input = socket.getInputStream()

    override fun read(): Int {
        armTimeout()
        return input.read()
    }

    override fun read(b: ByteArray, off: Int, len: Int): Int {
        armTimeout()
        return input.read(b, off, len)
    }

    private fun armTimeout() {
        val remaining = -deadline.elapsedNow()
        if (!remaining.isPositive()) throw SocketTimeoutException("read deadline exceeded")
        socket.soTimeout = remaining.inWholeMilliseconds.coerceIn(1, Int.MAX_VALUE.toLong()).toInt()
    }
}
