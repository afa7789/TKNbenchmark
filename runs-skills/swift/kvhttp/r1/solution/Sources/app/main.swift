import Foundation
import KVServer

let arguments = CommandLine.arguments
guard arguments.count == 2, let port = UInt16(arguments[1]), port != 0 else {
    FileHandle.standardError.write(Data("usage: \(arguments.first ?? "app") <port>\n".utf8))
    exit(2)
}

do {
    try await Server(port: port).run()
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
