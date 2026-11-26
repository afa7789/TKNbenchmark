package kvhttp

import com.sun.net.httpserver.HttpServer
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.Executors
import kotlin.system.exitProcess

private const val BACKLOG = 1024

/** Entry point: `app <port>` serves the key-value API on 127.0.0.1. */
fun main(args: Array<String>) {
    if (args.size != 1) {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }
    val port = args[0].toIntOrNull()?.takeIf { it in 0..65535 } ?: run {
        System.err.println("invalid port: ${args[0]}")
        exitProcess(2)
    }

    val address = InetSocketAddress(InetAddress.getLoopbackAddress(), port)
    HttpServer.create(address, BACKLOG).apply {
        createContext("/", KvHandler(KvStore()))
        executor = Executors.newVirtualThreadPerTaskExecutor()
        start()
    }
}
