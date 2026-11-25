/// A parsed HTTP request.
public struct HTTPRequest: Sendable {
    public var method: String
    public var target: String
    public var version: String
    /// Header fields in arrival order; names are lowercased.
    public var headers: [(name: String, value: String)]
    public var body: [UInt8]

    public init(
        method: String,
        target: String,
        version: String = "HTTP/1.1",
        headers: [(name: String, value: String)] = [],
        body: [UInt8] = []
    ) {
        self.method = method
        self.target = target
        self.version = version
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? {
        let name = name.lowercased()
        return headers.first { $0.name == name }?.value
    }

    /// Whether the client wants the connection kept open after this request.
    public var isKeepAlive: Bool {
        let tokens = header("connection")?.lowercased()
            .split(separator: ",").map { $0.trimmingWhitespace() } ?? []
        if tokens.contains("close") { return false }
        return version == "HTTP/1.1" || tokens.contains("keep-alive")
    }
}

/// An HTTP response with a fully materialised body.
public struct HTTPResponse: Sendable {
    public var status: Int
    public var contentType: String?
    public var body: [UInt8]

    public init(status: Int, contentType: String? = nil, body: [UInt8] = []) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }

    public init(status: Int, contentType: String, text: String) {
        self.init(status: status, contentType: contentType, body: Array(text.utf8))
    }

    /// Status line and headers, terminated by the blank line.
    func serializedHead(keepAlive: Bool) -> [UInt8] {
        var head = "HTTP/1.1 \(status) \(Self.reasonPhrase(for: status))\r\n"
        if let contentType {
            head += "Content-Type: \(contentType)\r\n"
        }
        head += "Content-Length: \(body.count)\r\n"
        head += keepAlive ? "Connection: keep-alive\r\n" : "Connection: close\r\n"
        head += "\r\n"
        return Array(head.utf8)
    }

    static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 201: "Created"
        case 204: "No Content"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 408: "Request Timeout"
        case 413: "Content Too Large"
        case 431: "Request Header Fields Too Large"
        case 500: "Internal Server Error"
        case 501: "Not Implemented"
        case 505: "HTTP Version Not Supported"
        default: "Unknown"
        }
    }
}

extension StringProtocol {
    func trimmingWhitespace() -> SubSequence {
        let isSpace: (Character) -> Bool = { $0 == " " || $0 == "\t" }
        let start = firstIndex { !isSpace($0) } ?? endIndex
        let end = lastIndex { !isSpace($0) }.map(index(after:)) ?? start
        return self[start..<end]
    }
}
