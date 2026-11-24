import Darwin

/// Failures while reading a request; each maps onto an HTTP error response.
enum RequestError: Error {
    case malformed
    case headersTooLarge
    case bodyTooLarge
    case unsupportedTransferEncoding

    var response: HTTPResponse {
        switch self {
        case .malformed: HTTPResponse(400)
        case .headersTooLarge: HTTPResponse(431)
        case .bodyTooLarge: HTTPResponse(413)
        case .unsupportedTransferEncoding: HTTPResponse(501)
        }
    }
}

/// Blocking HTTP/1.1 connection over a connected socket. Owns and closes the descriptor.
final class Connection {
    static let maxHeaderSize = 64 * 1024
    private static let readChunkSize = 64 * 1024
    private static let headerTerminator: [UInt8] = Array("\r\n\r\n".utf8)

    private let fd: Int32
    private var buffer: [UInt8] = []

    init(fd: Int32) {
        self.fd = fd
    }

    deinit {
        close(fd)
    }

    /// Serves requests until the peer closes, asks to close, or an error occurs.
    func serve(router: Router) {
        while true {
            let request: HTTPRequest
            do {
                guard let next = try readRequest() else { return }
                request = next
            } catch let error as RequestError {
                _ = send(error.response.serialized(keepAlive: false))
                return
            } catch {
                return
            }

            let keepAlive = request.isKeepAlive
            let response = router.handle(request)
            guard send(response.serialized(keepAlive: keepAlive)), keepAlive else { return }
        }
    }

    // MARK: - Reading

    /// Reads the next request, or returns `nil` if the peer closed cleanly between requests.
    private func readRequest() throws -> HTTPRequest? {
        var scanFrom = 0
        let headerEnd: Int
        while true {
            if let end = findHeaderTerminator(from: scanFrom) {
                headerEnd = end
                break
            }
            guard buffer.count <= Self.maxHeaderSize else { throw RequestError.headersTooLarge }
            scanFrom = max(0, buffer.count - (Self.headerTerminator.count - 1))
            guard try fill() else {
                if buffer.isEmpty { return nil }
                throw RequestError.malformed
            }
        }

        var request = try parseHead(buffer[..<headerEnd])
        let bodyStart = headerEnd + Self.headerTerminator.count

        if request.header("transfer-encoding") != nil {
            throw RequestError.unsupportedTransferEncoding
        }
        let contentLength: Int
        if let raw = request.header("content-length") {
            guard let value = Int(raw), value >= 0 else { throw RequestError.malformed }
            contentLength = value
        } else {
            contentLength = 0
        }
        guard contentLength <= Router.maxValueSize else { throw RequestError.bodyTooLarge }

        let requestEnd = bodyStart + contentLength
        if buffer.count < requestEnd {
            buffer.reserveCapacity(requestEnd)
        }
        while buffer.count < requestEnd {
            guard try fill() else { throw RequestError.malformed }
        }

        request.body = Array(buffer[bodyStart..<requestEnd])
        buffer.removeFirst(requestEnd)
        return request
    }

    private func findHeaderTerminator(from start: Int) -> Int? {
        let terminator = Self.headerTerminator
        guard buffer.count >= terminator.count else { return nil }
        var i = start
        while i <= buffer.count - terminator.count {
            if buffer[i] == terminator[0], buffer[i + 1] == terminator[1],
               buffer[i + 2] == terminator[2], buffer[i + 3] == terminator[3] {
                return i
            }
            i += 1
        }
        return nil
    }

    private func parseHead(_ bytes: ArraySlice<UInt8>) throws -> HTTPRequest {
        // Header bytes outside UTF-8 are replaced; routing only needs ASCII.
        let text = String(decoding: bytes, as: UTF8.self)
        var lines = text.split(separator: "\r\n", omittingEmptySubsequences: false)[...]
        guard let requestLine = lines.popFirst() else { throw RequestError.malformed }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { throw RequestError.malformed }

        var headers: [(name: String, value: String)] = []
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { throw RequestError.malformed }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingWhitespace()
            headers.append((name: name, value: value))
        }

        return HTTPRequest(
            method: String(parts[0]),
            target: String(parts[1]),
            version: String(parts[2]),
            headers: headers,
            body: []
        )
    }

    /// Appends available bytes to the buffer. Returns `false` on EOF.
    private func fill() throws -> Bool {
        var chunk = [UInt8](repeating: 0, count: Self.readChunkSize)
        while true {
            let n = chunk.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
            if n > 0 {
                buffer.append(contentsOf: chunk[..<n])
                return true
            }
            if n == 0 { return false }
            if errno == EINTR { continue }
            throw SocketError.system("recv", errno)
        }
    }

    // MARK: - Writing

    /// Writes all bytes. Returns `false` if the peer went away.
    private func send(_ bytes: [UInt8]) -> Bool {
        bytes.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.send(fd, raw.baseAddress! + offset, raw.count - offset, 0)
                if n > 0 {
                    offset += n
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }
}

private extension Substring {
    func trimmingWhitespace() -> String {
        let isSpace: (Character) -> Bool = { $0 == " " || $0 == "\t" }
        guard let first = firstIndex(where: { !isSpace($0) }),
              let last = lastIndex(where: { !isSpace($0) })
        else { return "" }
        return String(self[first...last])
    }
}
