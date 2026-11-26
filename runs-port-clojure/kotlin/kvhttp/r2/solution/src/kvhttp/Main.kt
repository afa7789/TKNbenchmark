package kvhttp

import com.sun.net.httpserver.HttpServer
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.Executors
import kotlin.system.exitProcess

private const val BACKLOG = 1024

fun main(args: Array<String>) {
    val port = args.firstOrNull()?.toIntOrNull()?.takeIf { it in 1..65535 }
    if (port == null) {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }

    val address = InetSocketAddress(InetAddress.getLoopbackAddress(), port)
    HttpServer.create(address, BACKLOG).apply {
        createContext("/", KvHandler(Store()))
        executor = Executors.newVirtualThreadPerTaskExecutor()
        start()
    }
}
