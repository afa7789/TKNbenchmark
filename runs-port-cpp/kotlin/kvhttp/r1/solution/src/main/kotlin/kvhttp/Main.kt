package kvhttp

import java.io.BufferedOutputStream
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors
import kotlin.system.exitProcess

private const val IO_TIMEOUT_MS = 30_000
private val LIMITS = Limits()

private fun serveConnection(client: Socket, router: Router) {
    client.use { socket ->
        socket.tcpNoDelay = true
        // Don't let an idle or stalled client pin a thread forever.
        socket.soTimeout = IO_TIMEOUT_MS
        try {
            val response = when (val result = readRequest(socket.getInputStream(), LIMITS)) {
                is ReadResult.Ok -> try {
                    router.handle(result.request)
                } catch (e: Exception) {
                    System.err.println("handler failed: $e")
                    Response.empty(500)
                }
                is ReadResult.Error -> result.response
                ReadResult.Closed -> null
            }
            if (response != null) {
                writeResponse(BufferedOutputStream(socket.getOutputStream(), 64 * 1024), response)
            }
            // Half-close so the client reads the full response before the FIN.
            socket.shutdownOutput()
        } catch (_: IOException) {
            // Peer went away; nothing more to do.
        }
    }
}

private fun parsePort(s: String): Int? = s.toIntOrNull()?.takeIf { it in 1..65535 && s.all(Char::isDigit) }

fun main(args: Array<String>) {
    if (args.size != 1) {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }
    val port = parsePort(args[0]) ?: run {
        System.err.println("invalid port: ${args[0]}")
        exitProcess(2)
    }

    val router = Router(KvStore())
    val listener = try {
        ServerSocket().apply {
            reuseAddress = true
            bind(InetSocketAddress(InetAddress.getLoopbackAddress(), port), 1024)
        }
    } catch (e: IOException) {
        System.err.println("fatal: cannot listen on port $port: ${e.message}")
        exitProcess(1)
    }

    // One virtual thread per connection: connections are short-lived and blocking I/O is simplest.
    Executors.newVirtualThreadPerTaskExecutor().use { executor ->
        listener.use {
            while (true) {
                val client = try {
                    listener.accept()
                } catch (e: IOException) {
                    System.err.println("accept failed: ${e.message}")
                    Thread.sleep(10)
                    continue
                }
                executor.execute { serveConnection(client, router) }
            }
        }
    }
}
