// kvhttp: an HTTP/1.1 in-memory key-value server.
// Usage: ./app <port>  (listens on 127.0.0.1)
package kvhttp

import java.io.IOException
import kotlin.system.exitProcess

private fun parsePort(s: String): Int? =
    s.takeIf { it.isNotEmpty() && it.all(Char::isDigit) }?.toIntOrNull()?.takeIf { it in 1..65535 }

fun main(args: Array<String>) {
    val port = args.singleOrNull()?.let(::parsePort)
    if (port == null) {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }
    try {
        Server(port, Router(KeyValueStore())).serve()
    } catch (e: IOException) {
        System.err.println("listen: ${e.message}")
        exitProcess(1)
    }
    exitProcess(1)
}
