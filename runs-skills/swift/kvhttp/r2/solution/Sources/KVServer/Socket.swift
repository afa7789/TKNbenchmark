#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A failed system call, carrying `errno`.
public struct SocketError: Error, CustomStringConvertible {
    public let operation: String
    public let code: Int32

    init(_ operation: String, code: Int32 = errno) {
        self.operation = operation
        self.code = code
    }

    public var description: String {
        "\(operation): \(String(cString: strerror(code)))"
    }
}

/// Thin wrappers over BSD socket calls for a connected TCP stream.
struct StreamSocket: Sendable {
    let fd: Int32

    func setOption(_ level: Int32, _ name: Int32, _ value: Int32) {
        var value = value
        _ = setsockopt(fd, level, name, &value, socklen_t(MemoryLayout<Int32>.size))
    }

    func setTimeout(_ name: Int32, seconds: Int) {
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, name, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Reads available bytes into `scratch` and appends them to `buffer`.
    /// Returns `false` on end of stream, timeout, or error.
    func read(appendingTo buffer: inout [UInt8], scratch: inout [UInt8]) -> Bool {
        while true {
            let n = scratch.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
            if n > 0 {
                buffer.append(contentsOf: scratch[0..<n])
                return true
            }
            if n < 0, errno == EINTR { continue }
            return false
        }
    }

    /// Writes all of `bytes`. Returns `false` if the peer went away or the write timed out.
    @discardableResult
    func write(_ bytes: [UInt8]) -> Bool {
        bytes.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = send(fd, raw.baseAddress! + offset, raw.count - offset, Self.sendFlags)
                if n > 0 {
                    offset += n
                } else if n < 0, errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }

    func close() {
        _ = closeSocket(fd)
    }

    #if canImport(Darwin)
    private static let sendFlags: Int32 = 0  // SO_NOSIGPIPE is set per socket instead.
    #else
    private static let sendFlags = Int32(MSG_NOSIGNAL)
    #endif
}

private func closeSocket(_ fd: Int32) -> Int32 {
    #if canImport(Darwin)
    Darwin.close(fd)
    #else
    Glibc.close(fd)
    #endif
}

/// A listening IPv4 TCP socket.
struct ListeningSocket: Sendable {
    let fd: Int32

    init(host: String, port: UInt16, backlog: Int32) throws(SocketError) {
        var address = sockaddr_in()
        #if canImport(Darwin)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            throw SocketError("invalid IPv4 address \(host)", code: EINVAL)
        }

        #if canImport(Darwin)
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #else
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard fd >= 0 else { throw SocketError("socket") }

        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let error = SocketError("bind \(host):\(port)")
            _ = closeSocket(fd)
            throw error
        }
        guard listen(fd, backlog) == 0 else {
            let error = SocketError("listen")
            _ = closeSocket(fd)
            throw error
        }
        self.fd = fd
    }

    /// Blocks until a client connects. Transient failures are retried.
    func accept() throws(SocketError) -> StreamSocket {
        while true {
            #if canImport(Darwin)
            let client = Darwin.accept(fd, nil, nil)
            #else
            let client = Glibc.accept(fd, nil, nil)
            #endif
            if client >= 0 { return StreamSocket(fd: client) }
            switch errno {
            case EINTR, ECONNABORTED, EAGAIN:
                continue
            case EMFILE, ENFILE, ENOBUFS, ENOMEM:
                // Out of descriptors or memory: back off briefly and let connections drain.
                usleep(10_000)
            default:
                throw SocketError("accept")
            }
        }
    }
}
