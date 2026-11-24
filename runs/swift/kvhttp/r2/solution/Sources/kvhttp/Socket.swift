#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct SocketError: Error, CustomStringConvertible {
    let operation: String
    let code: Int32

    init(_ operation: String, code: Int32 = errno) {
        self.operation = operation
        self.code = code
    }

    var description: String {
        "\(operation) failed: \(String(cString: strerror(code)))"
    }
}

/// A thin owner of a connected TCP socket descriptor. Closes the descriptor on deinit.
private let sendBytes = send

final class Socket {
    let descriptor: Int32

    init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)
    }

    func setOption<Value>(_ level: Int32, _ name: Int32, _ value: Value) {
        _ = withUnsafeBytes(of: value) { raw in
            setsockopt(descriptor, level, name, raw.baseAddress, socklen_t(raw.count))
        }
    }

    /// Receives up to `maxBytes` bytes and appends them to `buffer`.
    /// Returns the number of bytes read; `0` means the peer closed the connection.
    func receive(into buffer: inout [UInt8], maxBytes: Int) throws -> Int {
        let start = buffer.count
        while true {
            buffer.append(contentsOf: repeatElement(0, count: maxBytes))
            let received = buffer.withUnsafeMutableBytes { raw in
                recv(descriptor, raw.baseAddress! + start, maxBytes, 0)
            }
            buffer.removeLast(maxBytes - max(received, 0))
            if received >= 0 { return received }
            if errno == EINTR { continue }
            throw SocketError("recv")
        }
    }

    func send(_ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let sent = bytes.withUnsafeBytes { raw in
                sendBytes(descriptor, raw.baseAddress! + offset, bytes.count - offset, 0)
            }
            if sent < 0 {
                if errno == EINTR { continue }
                throw SocketError("send")
            }
            offset += sent
        }
    }

    func shutdownWrite() {
        shutdown(descriptor, SHUT_WR)
    }
}
