package kvhttp

import java.io.IOException
import kotlin.system.exitProcess

fun main(args: Array<String>) {
    if (args.size != 1) {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }
    val port = args[0].takeIf { s -> s.all { it.isDigit() } }?.toIntOrNull()?.takeIf { it in 1..65535 }
    if (port == null) {
        System.err.println("invalid port: ${args[0]}")
        exitProcess(2)
    }
    try {
        KvServer().serve(port)
    } catch (e: IOException) {
        System.err.println("listen: ${e.message}")
        exitProcess(1)
    }
}
