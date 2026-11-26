// kvhttp: an in-memory HTTP/1.1 key-value server. Usage: app <port>
package kvhttp

import java.io.IOException
import kotlin.system.exitProcess

fun main(args: Array<String>) {
    val port = args.singleOrNull()?.toIntOrNull()?.takeIf { it in 1..65535 }
    if (port == null) {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }
    try {
        Server(port, Router(KvStore())).run()
    } catch (e: IOException) {
        System.err.println("kvhttp: ${e.message}")
        exitProcess(1)
    }
}
