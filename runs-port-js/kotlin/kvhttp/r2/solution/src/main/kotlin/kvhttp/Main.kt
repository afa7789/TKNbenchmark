package kvhttp

import kotlin.system.exitProcess

fun main(args: Array<String>) {
    val port = args.singleOrNull()?.toIntOrNull()
    if (port == null || port !in 1..65535) {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }
    val server = HttpServer(KvApp())
    server.start("127.0.0.1", port)
    Runtime.getRuntime().addShutdownHook(Thread { server.close() })
}
