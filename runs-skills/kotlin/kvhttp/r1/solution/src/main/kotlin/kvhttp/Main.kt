package kvhttp

import com.sun.net.httpserver.HttpServer
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.Executors
import kotlin.system.exitProcess

fun main(args: Array<String>) {
    val port = args.singleOrNull()?.toIntOrNull()?.takeIf { it in 1..65535 }
    if (port == null) {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }
    val server = HttpServer.create(InetSocketAddress(InetAddress.getLoopbackAddress(), port), 1024)
    server.createContext("/", KvHandler(KvStore()))
    server.executor = Executors.newVirtualThreadPerTaskExecutor()
    server.start()
}
