package kvhttp

import kotlin.system.exitProcess

fun main(args: Array<String>) {
    if (args.size != 1) {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }
    val port = args[0].takeIf { arg -> arg.isNotEmpty() && arg.all { it in '0'..'9' } }
        ?.toIntOrNull()
        ?.takeIf { it in 1..65535 }
    if (port == null) {
        System.err.println("invalid port: ${args[0]}")
        exitProcess(2)
    }

    try {
        val server = Server(ServerOptions(port = port), Router(KvStore()))
        server.listen()
        server.run()
    } catch (e: Exception) {
        System.err.println("fatal: ${e.message}")
        exitProcess(1)
    }
}
