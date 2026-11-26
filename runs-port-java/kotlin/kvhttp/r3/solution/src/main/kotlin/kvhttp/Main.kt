package kvhttp

import kotlin.system.exitProcess

fun main(args: Array<String>) {
    if (args.size != 1) {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }
    val port = args[0].toIntOrNull()?.takeIf { it in 0..65535 } ?: run {
        System.err.println("invalid port: ${args[0]}")
        exitProcess(2)
    }
    KvServer().start(port)
}
