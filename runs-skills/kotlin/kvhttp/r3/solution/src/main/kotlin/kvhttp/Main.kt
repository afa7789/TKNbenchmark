package kvhttp

import kotlin.system.exitProcess

fun main(args: Array<String>) {
    val port = args.singleOrNull()?.toIntOrNull()?.takeIf { it in 1..65535 }
    if (port == null) {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }
    KvServer().start(port)
}
