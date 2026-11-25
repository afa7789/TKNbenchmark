import KVServer

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

let arguments = CommandLine.arguments
guard arguments.count == 2, let port = UInt16(arguments[1]), port > 0 else {
    fputs("usage: \(arguments.first ?? "app") <port>\n", stderr)
    exit(2)
}

// Peers that disconnect mid-write must not kill the process.
signal(SIGPIPE, SIG_IGN)

do {
    try KVHTTPServer(port: port).run()
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
