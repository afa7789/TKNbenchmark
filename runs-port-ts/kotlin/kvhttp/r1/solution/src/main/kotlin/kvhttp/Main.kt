package kvhttp

import kotlin.system.exitProcess

private fun parsePort(raw: String?): Int =
    raw?.toIntOrNull()?.takeIf { it in 1..65535 } ?: run {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }

fun main(args: Array<String>) {
    val port = parsePort(args.firstOrNull())
    val server = try {
        KvServer().start("127.0.0.1", port)
    } catch (e: Exception) {
        System.err.println("server error: ${e.message}")
        exitProcess(1)
    }
    Runtime.getRuntime().addShutdownHook(Thread { server.stop(0) })
    System.err.println("kvhttp listening on 127.0.0.1:$port")
}
