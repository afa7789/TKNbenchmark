package kvhttp

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.util.concurrent.Executors
import kotlin.system.exitProcess

private const val BACKLOG = 1024

/** Entry point: `app <port>` serves the kvhttp API on 127.0.0.1:<port>. */
fun main(args: Array<String>) {
    val port = args.singleOrNull()?.toIntOrNull()?.takeIf { it in 1..65535 }
    if (port == null) {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }

    val server = HttpServer.create(InetSocketAddress("127.0.0.1", port), BACKLOG).apply {
        createContext("/", KvHandler(Store()))
        executor = Executors.newVirtualThreadPerTaskExecutor()
    }
    server.start()
}
