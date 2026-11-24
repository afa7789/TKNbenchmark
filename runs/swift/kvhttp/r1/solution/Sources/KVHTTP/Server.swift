import Darwin
import Foundation

struct ServerError: Error, CustomStringConvertible {
    let operation: String
    let code: Int32

    var description: String { "\(operation) failed: \(String(cString: strerror(code)))" }
}

/// A thread-per-connection HTTP server bound to the loopback interface.
final class Server: Sendable {
    private static let ioTimeoutSeconds = 10

    private let router: Router
    private let listener: Int32

    init(port: UInt16, router: Router) throws(ServerError) {
        self.router = router

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError(operation: "socket", code: errno) }

        var enable: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &enable, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw ServerError(operation: "bind", code: code)
        }
        guard listen(fd, SOMAXCONN) == 0 else {
            let code = errno
            close(fd)
            throw ServerError(operation: "listen", code: code)
        }
        listener = fd
    }

    /// Accepts connections forever, serving each on its own thread.
    func run() -> Never {
        while true {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { continue }
            configure(client: client)
            Thread.detachNewThread { [self] in
                serve(client)
            }
        }
    }

    private func configure(client fd: Int32) {
        var enable: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enable, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: Self.ioTimeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private func serve(_ fd: Int32) {
        let connection = Connection(fd: fd)
        do {
            let request = try connection.readRequest()
            connection.send(router.handle(request))
        } catch {
            if let response = error.response {
                connection.send(response)
            }
        }
    }
}
