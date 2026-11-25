import Foundation

/// A parsed HTTP/1.x request.
public struct HTTPRequest: Sendable, Equatable {
    public var method: String
    public var target: String
    public var minorVersion: Int
    public var headers: [(name: String, value: String)]
    public var body: Data

    public init(method: String, target: String, minorVersion: Int = 1, headers: [(name: String, value: String)] = [], body: Data = Data()) {
        self.method = method
        self.target = target
        self.minorVersion = minorVersion
        self.headers = headers
        self.body = body
    }

    /// The request target without any query string or fragment.
    public var path: Substring {
        target.prefix { $0 != "?" && $0 != "#" }
    }

    /// First value of the header `name` (case-insensitive).
    public func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// Whether the client wants the connection kept open after this request.
    public var keepAlive: Bool {
        let tokens = (header("Connection") ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        if tokens.contains("close") { return false }
        return minorVersion >= 1 || tokens.contains("keep-alive")
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.method == rhs.method && lhs.target == rhs.target && lhs.minorVersion == rhs.minorVersion
            && lhs.body == rhs.body && lhs.headers.elementsEqual(rhs.headers) { $0 == $1 }
    }
}

/// An HTTP response ready to be serialized.
public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [(name: String, value: String)]
    public var body: Data

    public init(status: Int, headers: [(name: String, value: String)] = [], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// Wire representation. `Content-Length` and `Connection` are always set by this method.
    public func serialized(keepAlive: Bool) -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reasonPhrase(status))\r\n"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: \(keepAlive ? "keep-alive" : "close")\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    static func reasonPhrase(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 201: "Created"
        case 204: "No Content"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 408: "Request Timeout"
        case 411: "Length Required"
        case 413: "Content Too Large"
        case 431: "Request Header Fields Too Large"
        case 500: "Internal Server Error"
        case 501: "Not Implemented"
        case 505: "HTTP Version Not Supported"
        default: "Unknown"
        }
    }
}
