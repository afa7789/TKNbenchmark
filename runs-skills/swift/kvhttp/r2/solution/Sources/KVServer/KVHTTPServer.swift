import Foundation

/// HTTP/1.1 front end for a `KVStore`, using one thread per connection.
public struct KVHTTPServer: Sendable {
    public let host: String
    public let port: UInt16
    private let router: Router

    public init(host: String = "127.0.0.1", port: UInt16, store: KVStore = KVStore()) {
        self.host = host
        self.port = port
        self.router = Router(store: store)
    }

    /// Binds and serves forever; only returns by throwing.
    public func run() throws(SocketError) -> Never {
        let listener = try ListeningSocket(host: host, port: port, backlog: 1024)
        let router = router
        while true {
            let client = try listener.accept()
            Thread.detachNewThread {
                Connection(socket: client, router: router).serve()
            }
        }
    }
}
