/// Errors that terminate a connection after an error response is sent.
public enum HTTPParseError: Error, Equatable {
    case badRequest
    case headersTooLarge
    case bodyTooLarge
    case unsupportedTransferEncoding
    case unsupportedVersion

    var status: Int {
        switch self {
        case .badRequest: 400
        case .headersTooLarge: 431
        case .bodyTooLarge: 413
        case .unsupportedTransferEncoding: 501
        case .unsupportedVersion: 505
        }
    }
}

/// Everything before the body, plus the body length it announces.
struct RequestHead {
    var request: HTTPRequest
    var contentLength: Int
}

enum RequestParser {
    static let maxHeadSize = 64 * 1024
    private static let terminator: [UInt8] = Array("\r\n\r\n".utf8)

    /// Returns the index just past the `\r\n\r\n` that ends the head, searching from `start`.
    static func headEnd(in buffer: [UInt8], from start: Int) -> Int? {
        let lastStart = buffer.count - terminator.count
        guard lastStart >= 0 else { return nil }
        var i = max(0, start)
        while i <= lastStart {
            if buffer[i] == 13, buffer[i + 1] == 10, buffer[i + 2] == 13, buffer[i + 3] == 10 {
                return i + terminator.count
            }
            i += 1
        }
        return nil
    }

    /// Parses the request line and header fields in `bytes` (excluding the final blank line).
    static func parseHead(_ bytes: ArraySlice<UInt8>, maxBodySize: Int) throws(HTTPParseError) -> RequestHead {
        // Header bytes are treated as Latin-1-ish ASCII; anything non-UTF-8 is rejected.
        guard let text = String(validating: bytes, as: UTF8.self) else { throw .badRequest }
        var lines = text.split(separator: "\r\n", omittingEmptySubsequences: false)[...]
        // Tolerate stray empty lines before the request line (RFC 9112 §2.2).
        while lines.first?.isEmpty == true { lines = lines.dropFirst() }
        guard let requestLine = lines.popFirst() else { throw .badRequest }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, parts[1].first == "/" else { throw .badRequest }
        let version = String(parts[2])
        guard version == "HTTP/1.1" || version == "HTTP/1.0" else {
            throw version.hasPrefix("HTTP/") ? .unsupportedVersion : .badRequest
        }

        var headers: [(name: String, value: String)] = []
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { throw .badRequest }
            let name = line[..<colon]
            guard !name.isEmpty, !name.contains(" "), !name.contains("\t") else { throw .badRequest }
            headers.append((name.lowercased(), String(line[line.index(after: colon)...].trimmingWhitespace())))
        }

        let request = HTTPRequest(method: String(parts[0]), target: String(parts[1]), version: version, headers: headers)

        if request.header("transfer-encoding") != nil {
            throw .unsupportedTransferEncoding
        }

        var contentLength = 0
        let lengths = headers.filter { $0.name == "content-length" }.map(\.value)
        if let first = lengths.first {
            // Repeated Content-Length headers must agree.
            guard lengths.allSatisfy({ $0 == first }),
                  !first.isEmpty, first.utf8.allSatisfy({ (48...57).contains($0) })
            else { throw .badRequest }
            guard let value = Int(first), value <= maxBodySize else { throw .bodyTooLarge }
            contentLength = value
        }

        return RequestHead(request: request, contentLength: contentLength)
    }
}
