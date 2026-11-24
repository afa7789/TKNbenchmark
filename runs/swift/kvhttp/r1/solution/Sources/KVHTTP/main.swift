import Darwin

func fail(_ message: String) -> Never {
    fputs("kvhttp: \(message)\n", stderr)
    exit(2)
}

signal(SIGPIPE, SIG_IGN)

let arguments = CommandLine.arguments
guard arguments.count == 2, let port = UInt16(arguments[1]), port > 0 else {
    fail("usage: \(arguments.first ?? "app") <port>")
}

do {
    let server = try Server(port: port, router: Router(store: KeyValueStore()))
    server.run()
} catch {
    fail(error.description)
}
