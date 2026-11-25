import Foundation
import KVHTTP

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data("kvhttp: \(message)\n".utf8))
    exit(code)
}

let arguments = CommandLine.arguments
guard arguments.count == 2, let port = Int(arguments[1]) else {
    fail("usage: \(arguments.first ?? "app") <port>", code: 64)
}

let server: Server
do {
    server = try Server(port: port)
} catch {
    fail("cannot start server: \(error)", code: 1)
}
server.start { error in
    fail("listener failed: \(error)", code: 1)
}
dispatchMain()
