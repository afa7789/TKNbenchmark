import Foundation

/// Reasons a byte stream cannot be parsed as HTTP/1.x requests.
public enum HTTPParseError: Error, Equatable {
    case malformed
    case headersTooLarge
    case bodyTooLarge
    case unsupportedTransferEncoding
    case unsupportedVersion

    /// The status code to answer with before closing the connection.
    public var status: Int {
        switch self {
        case .malformed: 400
        case .headersTooLarge: 431
        case .bodyTooLarge: 413
        case .unsupportedTransferEncoding: 501
        case .unsupportedVersion: 505
        }
    }
}

/// Incremental HTTP/1.x request parser: feed bytes with `append`, pull requests with `next`.
public struct RequestParser: Sendable {
    public static let defaultMaxHeaderBytes = 16 * 1024

    private struct Head {
        var request: HTTPRequest
        var bodyStart: Int
        var contentLength: Int
    }

    private let maxHeaderBytes: Int
    private let maxBodyBytes: Int
    private var buffer: [UInt8] = []
    private var pending: Head?
    /// Where to resume searching for the end of the header block.
    private var scanOffset = 0

    public init(maxHeaderBytes: Int = defaultMaxHeaderBytes, maxBodyBytes: Int) {
        self.maxHeaderBytes = maxHeaderBytes
        self.maxBodyBytes = maxBodyBytes
    }

    /// Whether any unconsumed bytes are buffered.
    public var hasBufferedBytes: Bool { !buffer.isEmpty }

    public mutating func append(_ bytes: some Sequence<UInt8>) {
        buffer.append(contentsOf: bytes)
    }

    /// Returns the next complete request, or `nil` if more bytes are needed.
    public mutating func next() throws(HTTPParseError) -> HTTPRequest? {
        if pending == nil {
            guard let headerEnd = findHeaderEnd() else {
                if buffer.count > maxHeaderBytes { throw .headersTooLarge }
                return nil
            }
            guard headerEnd <= maxHeaderBytes else { throw .headersTooLarge }
            pending = try parseHead(buffer[..<headerEnd], bodyStart: headerEnd + 4)
        }
        guard let head = pending else { return nil }
        let end = head.bodyStart + head.contentLength
        guard buffer.count >= end else { return nil }

        var request = head.request
        request.body = Data(buffer[head.bodyStart..<end])
        buffer.removeSubrange(..<end)
        pending = nil
        scanOffset = 0
        return request
    }

    private mutating func findHeaderEnd() -> Int? {
        let terminator: [UInt8] = [13, 10, 13, 10]
        guard buffer.count >= 4 else { return nil }
        var index = scanOffset
        while index + 4 <= buffer.count {
            if buffer[index] == 13, buffer[index..<(index + 4)].elementsEqual(terminator) {
                return index
            }
            index += 1
        }
        scanOffset = max(0, buffer.count - 3)
        return nil
    }

    private func parseHead(_ bytes: ArraySlice<UInt8>, bodyStart: Int) throws(HTTPParseError) -> Head {
        guard let text = String(validating: bytes, as: UTF8.self) ?? String(bytes: bytes, encoding: .isoLatin1) else {
            throw .malformed
        }
        var lines = text.split(separator: "\r\n", omittingEmptySubsequences: false)[...]
        // Tolerate leading empty lines between requests (RFC 9112 §2.2).
        while lines.first?.isEmpty == true { lines.removeFirst() }
        guard let requestLine = lines.popFirst() else { throw .malformed }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, !parts[1].isEmpty,
              parts[0].allSatisfy(\.isHTTPTokenCharacter) else { throw .malformed }
        let minorVersion: Int
        switch parts[2] {
        case "HTTP/1.1": minorVersion = 1
        case "HTTP/1.0": minorVersion = 0
        default:
            throw parts[2].hasPrefix("HTTP/") ? .unsupportedVersion : .malformed
        }

        var headers: [(name: String, value: String)] = []
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { throw .malformed }
            let name = line[..<colon]
            guard !name.isEmpty, name.allSatisfy(\.isHTTPTokenCharacter) else { throw .malformed }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers.append((String(name), value))
        }

        let request = HTTPRequest(method: String(parts[0]), target: String(parts[1]), minorVersion: minorVersion, headers: headers)
        if let encoding = request.header("Transfer-Encoding"), encoding.lowercased() != "identity" {
            throw .unsupportedTransferEncoding
        }
        let lengths = headers.filter { $0.name.caseInsensitiveCompare("Content-Length") == .orderedSame }.map(\.value)
        var contentLength = 0
        if let first = lengths.first {
            guard lengths.allSatisfy({ $0 == first }), !first.isEmpty, first.utf8.allSatisfy({ (48...57).contains($0) }) else {
                throw .malformed
            }
            guard first.count <= 18, let length = Int(first) else { throw .bodyTooLarge }
            contentLength = length
        }
        guard contentLength <= maxBodyBytes else { throw .bodyTooLarge }
        return Head(request: request, bodyStart: bodyStart, contentLength: contentLength)
    }
}

private extension Character {
    /// `tchar` from RFC 9110 §5.6.2.
    var isHTTPTokenCharacter: Bool {
        guard let ascii = asciiValue, ascii > 32, ascii < 127 else { return false }
        return !"\"(),/:;<=>?@[\\]{}".contains(self)
    }
}
