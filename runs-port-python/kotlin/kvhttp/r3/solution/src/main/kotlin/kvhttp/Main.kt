package kvhttp

import kotlin.system.exitProcess

fun main(args: Array<String>) {
    val port = args.singleOrNull()
        ?.takeIf { arg -> arg.isNotEmpty() && arg.all { it in '0'..'9' } }
        ?.toIntOrNull()
        ?.takeIf { it in 1..65535 }
    if (port == null) {
        System.err.println("usage: app <port>")
        exitProcess(2)
    }
    Server(App()).serve("127.0.0.1", port)
}
