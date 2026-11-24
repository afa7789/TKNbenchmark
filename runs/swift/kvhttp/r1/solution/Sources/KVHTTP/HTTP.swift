/// A parsed HTTP request with its complete body.
struct HTTPRequest: Sendable {
    var method: String
    var target: String
    var version: String
    var headers: [(name: String, value: String)]
    var body: [UInt8]

    /// Path component of the request target, without any query string.
    var path: Substring {
        target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
    }

    func header(_ name: String) -> String? {
        headers.first { $0.name.lowercased() == name.lowercased() }?.value
    }
}

struct HTTPStatus: Sendable, Equatable {
    let code: Int
    let reason: String

    static let ok = HTTPStatus(code: 200, reason: "OK")
    static let created = HTTPStatus(code: 201, reason: "Created")
    static let noContent = HTTPStatus(code: 204, reason: "No Content")
    static let badRequest = HTTPStatus(code: 400, reason: "Bad Request")
    static let notFound = HTTPStatus(code: 404, reason: "Not Found")
    static let methodNotAllowed = HTTPStatus(code: 405, reason: "Method Not Allowed")
    static let requestTimeout = HTTPStatus(code: 408, reason: "Request Timeout")
    static let payloadTooLarge = HTTPStatus(code: 413, reason: "Content Too Large")
    static let headersTooLarge = HTTPStatus(code: 431, reason: "Request Header Fields Too Large")
    static let notImplemented = HTTPStatus(code: 501, reason: "Not Implemented")
}

struct HTTPResponse: Sendable {
    var status: HTTPStatus
    var headers: [(name: String, value: String)] = []
    var body: [UInt8] = []

    init(status: HTTPStatus, contentType: String? = nil, body: [UInt8] = []) {
        self.status = status
        self.body = body
        if let contentType {
            headers.append((name: "Content-Type", value: contentType))
        }
    }

    init(status: HTTPStatus, text: String) {
        self.init(status: status, contentType: "text/plain; charset=utf-8", body: Array(text.utf8))
    }

    /// Wire representation of the status line and headers, terminated by an empty line.
    /// The connection is always closed after the response, so we announce it.
    func serializedHead() -> [UInt8] {
        var head = "HTTP/1.1 \(status.code) \(status.reason)\r\n"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Array(head.utf8)
    }
}
