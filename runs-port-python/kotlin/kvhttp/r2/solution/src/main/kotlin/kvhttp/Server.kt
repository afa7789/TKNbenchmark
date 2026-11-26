package kvhttp

import java.io.BufferedInputStream
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors
import java.util.logging.Level
import java.util.logging.Logger

private const val BACKLOG = 1024
private const val READ_TIMEOUT_MS = 30_000

/** Serves one request per connection, each on its own virtual thread. */
class Server(private val app: App) {
    private val log = Logger.getLogger("kvhttp")

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
                socket.soTimeout = READ_TIMEOUT_MS
                socket.tcpNoDelay = true
                val response = try {
                    val request = RequestReader(BufferedInputStream(socket.getInputStream())).read() ?: return
                    app.handle(request)
                } catch (e: HttpException) {
                    Response(e.status)
                }
                socket.getOutputStream().apply {
                    write(response.serialize())
                    flush()
                }
                socket.shutdownOutput()
            } catch (_: IOException) {
                // Client went away or timed out; nothing useful to report.
            } catch (e: Exception) {
                log.log(Level.SEVERE, "unhandled error while serving request", e)
            }
        }
    }
}
