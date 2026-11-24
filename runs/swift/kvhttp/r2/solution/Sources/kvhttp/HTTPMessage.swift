/// A parsed HTTP/1.x request.
struct HTTPRequest {
    var method: String
    var path: String
    var version: String
    var headers: [(name: String, value: String)]
    var body: [UInt8]

    func header(_ name: String) -> String? {
        headers.first { $0.name.lowercased() == name.lowercased() }?.value
    }

    /// Whether the client wants the connection kept open after this request.
    var keepAlive: Bool {
        let connection = header("Connection")?.lowercased() ?? ""
        if version == "HTTP/1.0" {
            return connection.contains("keep-alive")
        }
        return !connection.contains("close")
    }
}

struct HTTPResponse {
    var status: Int
    var contentType: String?
    var body: [UInt8]

    init(status: Int, contentType: String? = nil, body: [UInt8] = []) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }

    init(status: Int, contentType: String, text: String) {
        self.init(status: status, contentType: contentType, body: Array(text.utf8))
    }

    func serialized(keepAlive: Bool) -> [UInt8] {
        var head = "HTTP/1.1 \(status) \(Self.reasonPhrase(for: status))\r\n"
        if let contentType {
            head += "Content-Type: \(contentType)\r\n"
        }
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: \(keepAlive ? "keep-alive" : "close")\r\n\r\n"
        var bytes = Array(head.utf8)
        bytes.reserveCapacity(bytes.count + body.count)
        bytes.append(contentsOf: body)
        return bytes
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
        case 411: "Length Required"
        case 413: "Content Too Large"
        case 431: "Request Header Fields Too Large"
        case 500: "Internal Server Error"
        case 501: "Not Implemented"
        default: "Unknown"
        }
    }
}
