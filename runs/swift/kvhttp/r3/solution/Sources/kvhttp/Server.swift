import Darwin
import Foundation

enum SocketError: Error, CustomStringConvertible {
    case system(String, Int32)

    var description: String {
        switch self {
        case let .system(call, code):
            "\(call) failed: \(String(cString: strerror(code)))"
        }
    }
}

/// Accepts TCP connections on 127.0.0.1 and serves each on its own thread.
///
/// A thread per connection keeps request handling simple, blocking code while
/// comfortably supporting the required number of simultaneous clients.
struct Server: Sendable {
    let port: UInt16
    let store: KeyValueStore
    var backlog: Int32 = 1024
    /// Idle connections are dropped after this many seconds without data.
    var readTimeout = 30

    func run() throws -> Never {
        signal(SIGPIPE, SIG_IGN)
        let listener = try makeListener()
        let router = Router(store: store)

        while true {
            let client = accept(listener, nil, nil)
            if client < 0 {
                if errno == EINTR || errno == ECONNABORTED { continue }
                if errno == EMFILE || errno == ENFILE {
                    usleep(10_000)
                    continue
                }
                throw SocketError.system("accept", errno)
            }
            configure(client: client)

            let thread = Thread {
                Connection(fd: client).serve(router: router)
            }
            thread.stackSize = 1 << 20
            thread.start()
        }
    }

    private func makeListener() throws -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system("socket", errno) }

        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw SocketError.system("bind", code)
        }
        guard listen(fd, backlog) == 0 else {
            let code = errno
            close(fd)
            throw SocketError.system("listen", code)
        }
        return fd
    }

    private func configure(client fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: readTimeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }
}
