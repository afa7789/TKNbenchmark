import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Accepts TCP connections on a loopback port and serves each on its own thread.
struct Server {
    let host: String
    let port: UInt16
    let router: Router

    /// Seconds a connection may sit idle in a read or write before it is dropped.
    var ioTimeout = 30

    func run() throws -> Never {
        signal(SIGPIPE, SIG_IGN)
        let listener = try makeListener()
        while true {
            let client = accept(listener.descriptor, nil, nil)
            if client < 0 {
                if errno == EINTR || errno == ECONNABORTED || errno == EMFILE || errno == ENFILE { continue }
                throw SocketError("accept")
            }
            let socket = Socket(descriptor: client)
            configure(socket)
            let router = self.router
            // `Socket` is only ever touched by the thread it is handed to.
            nonisolated(unsafe) let owned = socket
            Thread.detachNewThread {
                HTTPConnection(socket: owned).serve(using: router)
            }
        }
    }

    private func configure(_ socket: Socket) {
        let timeout = timeval(tv_sec: ioTimeout, tv_usec: 0)
        socket.setOption(SOL_SOCKET, SO_RCVTIMEO, timeout)
        socket.setOption(SOL_SOCKET, SO_SNDTIMEO, timeout)
        socket.setOption(IPPROTO_TCP, TCP_NODELAY, Int32(1))
        #if canImport(Darwin)
        socket.setOption(SOL_SOCKET, SO_NOSIGPIPE, Int32(1))
        #endif
    }

    private func makeListener() throws -> Socket {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw SocketError("socket") }
        let listener = Socket(descriptor: descriptor)
        listener.setOption(SOL_SOCKET, SO_REUSEADDR, Int32(1))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            throw SocketError("inet_pton", code: EINVAL)
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { throw SocketError("bind") }
        guard listen(descriptor, SOMAXCONN) == 0 else { throw SocketError("listen") }
        return listener
    }
}
