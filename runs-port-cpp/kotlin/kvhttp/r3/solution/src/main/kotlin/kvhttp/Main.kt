package kvhttp

import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.util.concurrent.Executors
import kotlin.system.exitProcess

private const val IO_TIMEOUT_MS = 30_000
private const val DRAIN_TIMEOUT_MS = 2_000
private const val MAX_DRAIN_BYTES = 64L * 1024 * 1024

private fun die(message: String, status: Int = 1): Nothing {
    System.err.println("kvhttp: $message")
    exitProcess(status)
}

private fun parsePort(arg: String): Int =
    arg.toIntOrNull()?.takeIf { it in 1..65535 } ?: die("invalid port '$arg'", 2)

/** Discards unread request bytes so closing does not send a RST that could clobber the reply. */
private fun drain(socket: Socket) {
    socket.soTimeout = DRAIN_TIMEOUT_MS
    val sink = ByteArray(16 * 1024)
    var total = 0L
    try {
        val input = socket.getInputStream()
        while (total < MAX_DRAIN_BYTES) {
            val n = input.read(sink)
            if (n <= 0) break
            total += n
        }
    } catch (_: IOException) {
        // Timeout or reset: nothing more to drain.
    }
}

private fun serveConnection(socket: Socket, router: Router) = socket.use {
    it.tcpNoDelay = true
    it.soTimeout = IO_TIMEOUT_MS
    val response = try {
        val request = readRequest(it.getInputStream()) ?: return
        router.handle(request)
    } catch (e: HttpException) {
        Response(e.status)
    } catch (e: Exception) {
        System.err.println("kvhttp: request failed: $e")
        Response(500)
    }
    try {
        writeResponse(it.getOutputStream(), response)
        it.shutdownOutput()
    } catch (_: IOException) {
        return
    }
    drain(it)
}

fun main(args: Array<String>) {
    if (args.size != 1) die("usage: app <port>", 2)
    val port = parsePort(args[0])

    val listener = try {
        ServerSocket().apply {
            reuseAddress = true
            bind(InetSocketAddress(InetAddress.getLoopbackAddress(), port), 1024)
        }
    } catch (e: IOException) {
        die("bind: ${e.message}")
    }

    val router = Router(Store())
    Executors.newVirtualThreadPerTaskExecutor().use { executor ->
        listener.use {
            while (true) {
                val socket = try {
                    it.accept()
                } catch (e: SocketException) {
                    System.err.println("kvhttp: accept: ${e.message}")
                    Thread.sleep(10)
                    continue
                }
                executor.execute { serveConnection(socket, router) }
            }
        }
    }
}
