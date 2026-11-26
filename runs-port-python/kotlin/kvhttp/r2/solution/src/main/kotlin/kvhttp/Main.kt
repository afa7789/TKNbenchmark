package kvhttp

import kotlin.system.exitProcess

fun main(args: Array<String>) {
    val port = args.singleOrNull()?.takeIf { it.isNotEmpty() && it.all(Char::isDigit) }?.toIntOrNull()
    if (port == null || port > 65535) {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }
    Server(App(Store())).serve("127.0.0.1", port)
}
