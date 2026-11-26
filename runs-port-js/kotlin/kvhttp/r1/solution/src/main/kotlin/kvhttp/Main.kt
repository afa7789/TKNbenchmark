package kvhttp

import com.sun.net.httpserver.HttpServer
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.Executors
import kotlin.system.exitProcess

private const val BACKLOG = 1024

fun main(args: Array<String>) {
    val port = args.singleOrNull()?.toIntOrNull()?.takeIf { it in 1..65535 }
    if (port == null) {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }

    val server = try {
        HttpServer.create(InetSocketAddress(InetAddress.getLoopbackAddress(), port), BACKLOG)
    } catch (e: java.io.IOException) {
        System.err.println(e.message)
        exitProcess(1)
    }
    server.executor = Executors.newVirtualThreadPerTaskExecutor()
    server.createContext("/", KvHandler(KvStore()))
    server.start()

    Runtime.getRuntime().addShutdownHook(Thread { server.stop(0) })
}
