import Darwin

/// Reasons a request could not be read off the wire.
enum RequestReadError: Error {
    /// The peer closed the connection before sending anything.
    case closedBeforeRequest
    case malformed
    case headersTooLarge
    case bodyTooLarge
    case unsupportedTransferEncoding
    case timedOut
    case io(errno: Int32)

    /// The response to send back, if the connection is still usable for one.
    var response: HTTPResponse? {
        switch self {
        case .closedBeforeRequest, .io: nil
        case .malformed: HTTPResponse(status: .badRequest)
        case .headersTooLarge: HTTPResponse(status: .headersTooLarge)
        case .bodyTooLarge: HTTPResponse(status: .payloadTooLarge)
        case .unsupportedTransferEncoding: HTTPResponse(status: .notImplemented)
        case .timedOut: HTTPResponse(status: .requestTimeout)
        }
    }
}

/// A blocking, single-request HTTP/1.1 connection over a connected socket.
struct Connection: ~Copyable {
    static let maxHeaderSize = 64 * 1024
    static let maxBodySize = 1 << 20
    private static let readChunkSize = 64 * 1024
    private static let headerTerminator: [UInt8] = Array("\r\n\r\n".utf8)

    private let fd: Int32

    init(fd: Int32) {
        self.fd = fd
    }

    deinit {
        // Half-close, then drain whatever the client still sends so the kernel
        // does not reset the connection and discard our response.
        Darwin.shutdown(fd, SHUT_WR)
        var scratch = [UInt8](repeating: 0, count: 4096)
        while scratch.withUnsafeMutableBytes({ recv(fd, $0.baseAddress, $0.count, 0) }) > 0 {}
        Darwin.close(fd)
    }

    func readRequest() throws(RequestReadError) -> HTTPRequest {
        var buffer: [UInt8] = []
        buffer.reserveCapacity(8 * 1024)

        var searchFrom = 0
        let headerEnd: Int
        while true {
            if let end = Self.find(Self.headerTerminator, in: buffer, from: searchFrom) {
                headerEnd = end
                break
            }
            guard buffer.count <= Self.maxHeaderSize else { throw .headersTooLarge }
            searchFrom = max(0, buffer.count - (Self.headerTerminator.count - 1))
            guard try receive(into: &buffer) > 0 else {
                throw buffer.isEmpty ? .closedBeforeRequest : .malformed
            }
        }

        var request = try Self.parseHead(buffer[..<headerEnd])
        let bodyStart = headerEnd + Self.headerTerminator.count
        let contentLength = try Self.contentLength(of: request)

        var body = Array(buffer[bodyStart...])
        guard body.count <= contentLength else { throw .malformed }
        body.reserveCapacity(contentLength)
        while body.count < contentLength {
            guard try receive(into: &body, limit: contentLength - body.count) > 0 else { throw .malformed }
        }
        request.body = body
        return request
    }

    func send(_ response: HTTPResponse) {
        var bytes = response.serializedHead()
        bytes.append(contentsOf: response.body)
        bytes.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let sent = Darwin.send(fd, raw.baseAddress! + offset, raw.count - offset, 0)
                if sent > 0 {
                    offset += sent
                } else if sent < 0 && errno == EINTR {
                    continue
                } else {
                    return
                }
            }
        }
    }

    // MARK: - Reading

    /// Appends up to `limit` received bytes to `buffer`; returns the count (0 on EOF).
    private func receive(into buffer: inout [UInt8], limit: Int = readChunkSize) throws(RequestReadError) -> Int {
        let wanted = min(limit, Self.readChunkSize)
        let oldCount = buffer.count
        var received = 0
        var failure: Int32 = 0
        buffer.append(contentsOf: repeatElement(0, count: wanted))
        while true {
            received = buffer.withUnsafeMutableBytes { raw in
                recv(fd, raw.baseAddress! + oldCount, wanted, 0)
            }
            if received >= 0 { break }
            failure = errno
            if failure != EINTR { break }
        }
        buffer.removeLast(wanted - max(received, 0))
        if received < 0 {
            throw failure == EAGAIN || failure == EWOULDBLOCK ? .timedOut : .io(errno: failure)
        }
        return received
    }

    // MARK: - Parsing

    private static func parseHead(_ bytes: ArraySlice<UInt8>) throws(RequestReadError) -> HTTPRequest {
        let text = String(decoding: bytes, as: UTF8.self)
        var lines = text.split(separator: "\r\n", omittingEmptySubsequences: false)[...]
        guard let requestLine = lines.popFirst() else { throw .malformed }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, parts[1].hasPrefix("/") || parts[1] == "*",
              parts[2].hasPrefix("HTTP/1.") else {
            throw .malformed
        }

        var headers: [(name: String, value: String)] = []
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { throw .malformed }
            let name = line[..<colon]
            guard !name.isEmpty, !name.contains(where: \.isWhitespace) else { throw .malformed }
            let value = line[line.index(after: colon)...].trimmingWhitespace()
            headers.append((name: String(name), value: String(value)))
        }

        return HTTPRequest(
            method: String(parts[0]),
            target: String(parts[1]),
            version: String(parts[2]),
            headers: headers,
            body: []
        )
    }

    private static func contentLength(of request: HTTPRequest) throws(RequestReadError) -> Int {
        if let encoding = request.header("Transfer-Encoding"), encoding.lowercased() != "identity" {
            throw .unsupportedTransferEncoding
        }
        let values = Set(request.headers.filter { $0.name.lowercased() == "content-length" }.map(\.value))
        guard let value = values.first else { return 0 }
        guard values.count == 1, !value.isEmpty, value.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else {
            throw .malformed
        }
        guard value.utf8.count <= 10, let length = Int(value), length <= maxBodySize else {
            throw .bodyTooLarge
        }
        return length
    }

    private static func find(_ needle: [UInt8], in haystack: [UInt8], from start: Int) -> Int? {
        guard haystack.count >= needle.count, start <= haystack.count - needle.count else { return nil }
        for index in start...(haystack.count - needle.count)
        where haystack[index] == needle[0] && haystack[index..<(index + needle.count)].elementsEqual(needle) {
            return index
        }
        return nil
    }
}

private extension Substring {
    func trimmingWhitespace() -> Substring {
        let isSpace: (Character) -> Bool = { $0 == " " || $0 == "\t" }
        guard let first = firstIndex(where: { !isSpace($0) }) else { return "" }
        let last = lastIndex(where: { !isSpace($0) })!
        return self[first...last]
    }
}
