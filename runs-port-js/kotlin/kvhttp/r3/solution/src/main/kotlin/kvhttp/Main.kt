package kvhttp

import java.io.IOException
import kotlin.system.exitProcess

fun main(args: Array<String>) {
    val port = args.singleOrNull()?.toIntOrNull()
    if (port == null || port !in 1..65535) {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }

    val server = KvServer()
    try {
        server.start("127.0.0.1", port)
    } catch (e: IOException) {
        System.err.println("kvhttp: ${e.message}")
        exitProcess(1)
    }
    Runtime.getRuntime().addShutdownHook(Thread(server::stop))
}
