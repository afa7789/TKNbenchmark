/// A parsed HTTP/1.x request.
struct HTTPRequest {
    var method: String
    var target: String
    var version: String
    /// Header names are lower-cased.
    var headers: [(name: String, value: String)]
    var body: [UInt8]

    func header(_ name: String) -> String? {
        headers.first { $0.name == name }?.value
    }

    /// Whether the client asked to reuse the connection after this request.
    var isKeepAlive: Bool {
        let connection = header("connection")?.lowercased()
        if version == "HTTP/1.0" {
            return connection == "keep-alive"
        }
        return connection != "close"
    }
}

/// An HTTP response with a fully materialised body.
struct HTTPResponse {
    var status: Int
    var body: [UInt8] = []
    var contentType: String?

    init(_ status: Int, body: [UInt8] = [], contentType: String? = nil) {
        self.status = status
        self.body = body
        self.contentType = contentType
    }

    func serialized(keepAlive: Bool) -> [UInt8] {
        var head = "HTTP/1.1 \(status) \(Self.reasonPhrase(status))\r\n"
        if let contentType {
            head += "Content-Type: \(contentType)\r\n"
        }
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: \(keepAlive ? "keep-alive" : "close")\r\n\r\n"
        return Array(head.utf8) + body
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
        case 413: "Content Too Large"
        case 431: "Request Header Fields Too Large"
        case 501: "Not Implemented"
        default: "Unknown"
        }
    }
}
