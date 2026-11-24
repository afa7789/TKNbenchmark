#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

func exitWithError(_ message: String, code: Int32) -> Never {
    fputs(message + "\n", stderr)
    exit(code)
}

let arguments = CommandLine.arguments
guard arguments.count == 2, let port = UInt16(arguments[1]), port > 0 else {
    exitWithError("usage: \(arguments.first ?? "app") <port>", code: 2)
}

do {
    try Server(host: "127.0.0.1", port: port, router: Router(store: KeyValueStore())).run()
} catch {
    exitWithError("kvhttp: \(error)", code: 1)
}
