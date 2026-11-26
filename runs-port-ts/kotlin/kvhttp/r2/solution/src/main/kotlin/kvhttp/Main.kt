package kvhttp

import java.io.IOException
import kotlin.system.exitProcess

private fun parsePort(arg: String?): Int {
    val port = arg?.toIntOrNull()
    if (port == null || port !in 1..65535) {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }
    return port
}

fun main(args: Array<String>) {
    val port = parsePort(args.firstOrNull())
    val server = KvServer()
    try {
        server.start(port)
    } catch (e: IOException) {
        System.err.println("server error: ${e.message}")
        exitProcess(1)
    }
    Runtime.getRuntime().addShutdownHook(Thread(server::close))
}
