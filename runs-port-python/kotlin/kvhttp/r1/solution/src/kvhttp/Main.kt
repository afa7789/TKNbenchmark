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
import kotlin.system.exitProcess

private const val READ_TIMEOUT_MILLIS = 30_000
private const val BACKLOG = 1024

private val log = Logger.getLogger("kvhttp")

/** Serves one request per connection, each on its own virtual thread. */
class Server(private val app: App) {
    fun serve(host: String, port: Int) {
        ServerSocket().use { listener ->
            listener.reuseAddress = true
            listener.bind(InetSocketAddress(InetAddress.getByName(host), port), BACKLOG)
            log.fine("listening on $host:$port")
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
                socket.soTimeout = READ_TIMEOUT_MILLIS
                socket.tcpNoDelay = true
                val response = try {
                    app.handle(readRequest(BufferedInputStream(socket.getInputStream())))
                } catch (e: HttpException) {
                    Response(e.status)
                } catch (e: IOException) {
                    return // peer went away or timed out; nothing to answer
                } catch (e: Exception) {
                    log.log(Level.SEVERE, "unhandled error while processing request", e)
                    Response(Status.INTERNAL_SERVER_ERROR)
                }
                socket.getOutputStream().apply {
                    write(response.encode())
                    flush()
                }
            } catch (_: IOException) {
                // Client disconnected while we were writing.
            }
        }
    }
}

fun main(args: Array<String>) {
    val usage = "usage: kvhttp <port> [--host HOST]"
    var host = "127.0.0.1"
    var port: Int? = null
    var i = 0
    while (i < args.size) {
        when (val arg = args[i]) {
            "--host" -> host = args.getOrNull(++i) ?: fail(usage)
            "-h", "--help" -> { println(usage); return }
            else -> port = arg.toIntOrNull()?.takeIf { it in 0..65535 } ?: fail("$usage\ninvalid port: $arg")
        }
        i++
    }
    Server(App()).serve(host, port ?: fail(usage))
}

private fun fail(message: String): Nothing {
    System.err.println(message)
    exitProcess(2)
}
