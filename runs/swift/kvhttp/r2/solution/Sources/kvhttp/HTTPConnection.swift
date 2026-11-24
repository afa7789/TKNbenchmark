/// Errors that terminate request parsing; each maps to an error response (or a silent close).
enum HTTPParseError: Error {
    case connectionClosed
    case malformed
    case headersTooLarge
    case bodyTooLarge(declaredLength: Int)
    case unsupportedTransferEncoding

    var response: HTTPResponse? {
        switch self {
        case .connectionClosed: nil
        case .malformed: HTTPResponse(status: 400)
        case .headersTooLarge: HTTPResponse(status: 431)
        case .bodyTooLarge: HTTPResponse(status: 413)
        case .unsupportedTransferEncoding: HTTPResponse(status: 501)
        }
    }
}

/// Reads HTTP/1.x requests from a socket and writes responses back.
final class HTTPConnection {
    static let maxHeaderSize = 64 * 1024
    private static let readChunkSize = 64 * 1024
    private static let headerTerminator: [UInt8] = Array("\r\n\r\n".utf8)

    private let socket: Socket
    private var buffer: [UInt8] = []

    init(socket: Socket) {
        self.socket = socket
    }

    /// Serves requests until the client asks to close, an error occurs, or the peer goes away.
    func serve(using router: Router) {
        do {
            while true {
                let request: HTTPRequest
                do {
                    request = try readRequest()
                } catch let error as HTTPParseError {
                    if case .bodyTooLarge(let length) = error {
                        // Consume the body so the client sees our response rather than a reset.
                        try? discard(byteCount: length)
                    }
                    if let response = error.response {
                        try socket.send(response.serialized(keepAlive: false))
                        socket.shutdownWrite()
                    }
                    return
                }
                let keepAlive = request.keepAlive
                try socket.send(router.handle(request).serialized(keepAlive: keepAlive))
                guard keepAlive else {
                    socket.shutdownWrite()
                    return
                }
            }
        } catch {
            // Socket-level failure (reset, timeout): nothing more can be sent.
        }
    }

    // MARK: - Parsing

    private func readRequest() throws -> HTTPRequest {
        let headEnd = try readHead()
        let head = String(decoding: buffer[..<headEnd], as: UTF8.self)
        buffer.removeFirst(headEnd + Self.headerTerminator.count)

        var lines = head.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { throw HTTPParseError.malformed }
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3,
              !requestLine[0].isEmpty,
              requestLine[1].hasPrefix("/") || requestLine[1].hasPrefix("http"),
              requestLine[2].hasPrefix("HTTP/1.")
        else { throw HTTPParseError.malformed }

        var headers: [(name: String, value: String)] = []
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { throw HTTPParseError.malformed }
            let name = line[..<colon].trimmingWhitespace()
            guard !name.isEmpty else { throw HTTPParseError.malformed }
            headers.append((String(name), String(line[line.index(after: colon)...].trimmingWhitespace())))
        }

        var request = HTTPRequest(
            method: String(requestLine[0]),
            path: Self.path(fromTarget: requestLine[1]),
            version: String(requestLine[2]),
            headers: headers,
            body: []
        )

        if let encoding = request.header("Transfer-Encoding"), encoding.lowercased() != "identity" {
            throw HTTPParseError.unsupportedTransferEncoding
        }
        let lengths = Set(headers.filter { $0.name.lowercased() == "content-length" }.map(\.value))
        if let lengthText = lengths.first {
            guard lengths.count == 1,
                  !lengthText.isEmpty,
                  lengthText.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
                  let length = Int(lengthText)
            else { throw HTTPParseError.malformed }
            guard length <= Router.maxValueSize else {
                throw HTTPParseError.bodyTooLarge(declaredLength: length)
            }
            request.body = try readBody(length: length)
        }
        return request
    }

    /// Strips an absolute-form prefix (`http://host`) and any query string from a request target.
    private static func path(fromTarget target: Substring) -> String {
        var path = target
        if !path.hasPrefix("/"), let schemeEnd = path.range(of: "://") {
            let afterScheme = path[schemeEnd.upperBound...]
            path = afterScheme.firstIndex(of: "/").map { afterScheme[$0...] } ?? "/"
        }
        if let query = path.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            path = path[..<query]
        }
        return String(path)
    }

    /// Reads until the end of the header block; returns the offset of the terminator.
    private func readHead() throws -> Int {
        var searchFrom = 0
        while true {
            if let end = buffer.firstRange(of: Self.headerTerminator, from: searchFrom) {
                return end
            }
            guard buffer.count <= Self.maxHeaderSize else { throw HTTPParseError.headersTooLarge }
            searchFrom = max(0, buffer.count - Self.headerTerminator.count + 1)
            if try socket.receive(into: &buffer, maxBytes: Self.readChunkSize) == 0 {
                throw HTTPParseError.connectionClosed
            }
        }
    }

    private func readBody(length: Int) throws -> [UInt8] {
        buffer.reserveCapacity(length)
        while buffer.count < length {
            if try socket.receive(into: &buffer, maxBytes: Self.readChunkSize) == 0 {
                throw HTTPParseError.connectionClosed
            }
        }
        let body = Array(buffer[..<length])
        buffer.removeFirst(length)
        return body
    }

    private func discard(byteCount: Int) throws {
        var remaining = byteCount - buffer.count
        buffer.removeAll(keepingCapacity: true)
        while remaining > 0 {
            let received = try socket.receive(into: &buffer, maxBytes: min(Self.readChunkSize, remaining))
            if received == 0 { return }
            remaining -= received
            buffer.removeAll(keepingCapacity: true)
        }
    }
}

private extension Array where Element == UInt8 {
    func firstRange(of pattern: [UInt8], from start: Int) -> Int? {
        guard count >= pattern.count else { return nil }
        var index = start
        while index <= count - pattern.count {
            if self[index] == pattern[0], self[index..<(index + pattern.count)].elementsEqual(pattern) {
                return index
            }
            index += 1
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
