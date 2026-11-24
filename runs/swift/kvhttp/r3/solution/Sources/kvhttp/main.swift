import Foundation

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data("kvhttp: \(message)\n".utf8))
    exit(code)
}

let arguments = CommandLine.arguments
guard arguments.count == 2, let port = UInt16(arguments[1]), port > 0 else {
    fail("usage: \(arguments.first ?? "app") <port>", code: 2)
}

do {
    try Server(port: port, store: KeyValueStore()).run()
} catch {
    fail("\(error)", code: 1)
}
