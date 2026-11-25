/// Incremental HTTP/1.x request parser. Feed bytes with ``append(_:)`` and pull
/// complete requests with ``next()``; leftover bytes are kept for pipelined requests.
public struct HTTPRequestParser: Sendable {
    public enum Result: Sendable, Equatable {
        case incomplete
        case request(HTTPRequest)
        /// The request is malformed or unacceptable; respond with the status and close.
        case failure(HTTPStatus)
    }

    private struct Head: Sendable {
        var method: String
        var path: String
        var headers: [(name: String, value: String)]
        var contentLength: Int
        var keepAlive: Bool
    }

    public let maxHeaderBytes: Int
    public let maxBodyBytes: Int

    private var buffer: [UInt8] = []
    /// Offset up to which `buffer` has been searched for the end of the header block.
    private var scannedOffset = 0
    /// A parsed head whose body has not fully arrived yet.
    private var pendingHead: Head?
    private var pendingBodyStart = 0

    public init(maxHeaderBytes: Int = 64 * 1024, maxBodyBytes: Int) {
        self.maxHeaderBytes = maxHeaderBytes
        self.maxBodyBytes = maxBodyBytes
    }

    public mutating func append(_ bytes: some Sequence<UInt8>) {
        buffer.append(contentsOf: bytes)
    }

    public mutating func next() -> Result {
        if pendingHead == nil {
            guard let headerEnd = findHeaderTerminator() else {
                return buffer.count > maxHeaderBytes ? .failure(.headersTooLarge) : .incomplete
            }
            switch Self.parseHead(buffer[..<headerEnd], maxBodyBytes: maxBodyBytes) {
            case .success(let head):
                pendingHead = head
                pendingBodyStart = headerEnd + 4
            case .failure(let status):
                return .failure(status)
            }
        }

        guard let head = pendingHead else { return .incomplete }
        let bodyEnd = pendingBodyStart + head.contentLength
        guard buffer.count >= bodyEnd else { return .incomplete }

        let request = HTTPRequest(
            method: head.method,
            path: head.path,
            headers: head.headers,
            body: Array(buffer[pendingBodyStart..<bodyEnd]),
            keepAlive: head.keepAlive
        )
        buffer.removeFirst(bodyEnd)
        pendingHead = nil
        scannedOffset = 0
        return .request(request)
    }

    /// Index of the `\r\n\r\n` that ends the header block, if present.
    private mutating func findHeaderTerminator() -> Int? {
        let cr = UInt8(ascii: "\r"), lf = UInt8(ascii: "\n")
        var index = max(0, scannedOffset - 3)
        while index + 3 < buffer.count {
            if buffer[index] == cr, buffer[index + 1] == lf, buffer[index + 2] == cr, buffer[index + 3] == lf {
                return index
            }
            index += 1
        }
        scannedOffset = buffer.count
        return nil
    }

    private enum HeadResult {
        case success(Head)
        case failure(HTTPStatus)
    }

    private static func parseHead(_ bytes: ArraySlice<UInt8>, maxBodyBytes: Int) -> HeadResult {
        let text = String(decoding: bytes, as: UTF8.self)
        var lines = text.split(separator: "\r\n", omittingEmptySubsequences: false)[...]
        guard let requestLine = lines.popFirst() else { return .failure(.badRequest) }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, parts[1].hasPrefix("/") else { return .failure(.badRequest) }
        let method = String(parts[0]), path = String(parts[1]), version = parts[2]
        guard version.hasPrefix("HTTP/") else { return .failure(.badRequest) }
        guard version == "HTTP/1.1" || version == "HTTP/1.0" else { return .failure(.versionNotSupported) }

        var headers: [(name: String, value: String)] = []
        var contentLength: Int?
        var connectionTokens: [Substring] = []

        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .failure(.badRequest) }
            let name = line[..<colon]
            guard !name.isEmpty, !name.contains(where: \.isWhitespace) else { return .failure(.badRequest) }
            let value = line[line.index(after: colon)...].trimmingWhitespace()
            headers.append((String(name), String(value)))

            switch name.lowercased() {
            case "content-length":
                guard !value.isEmpty, value.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }) else {
                    return .failure(.badRequest)
                }
                // Lengths beyond Int range are certainly too large.
                let length = Int(value) ?? Int.max
                if let contentLength, contentLength != length { return .failure(.badRequest) }
                contentLength = length
            case "transfer-encoding":
                return .failure(.notImplemented)
            case "connection":
                connectionTokens += value.lowercased().split(separator: ",").map { $0.trimmingWhitespace() }
            default:
                break
            }
        }

        let length = contentLength ?? 0
        guard length <= maxBodyBytes else { return .failure(.payloadTooLarge) }

        let keepAlive = version == "HTTP/1.1"
            ? !connectionTokens.contains("close")
            : connectionTokens.contains("keep-alive")

        return .success(Head(method: method, path: path, headers: headers, contentLength: length, keepAlive: keepAlive))
    }
}

extension Substring {
    fileprivate func trimmingWhitespace() -> Substring {
        let start = firstIndex { $0 != " " && $0 != "\t" } ?? endIndex
        let end = lastIndex { $0 != " " && $0 != "\t" }.map(index(after:)) ?? start
        return self[start..<end]
    }
}
