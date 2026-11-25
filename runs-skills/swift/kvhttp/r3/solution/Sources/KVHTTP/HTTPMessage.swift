import Foundation

public struct HTTPStatus: Sendable, Equatable, CustomStringConvertible {
    public let code: Int
    public let reason: String

    public var description: String { "\(code) \(reason)" }

    public static let ok = HTTPStatus(code: 200, reason: "OK")
    public static let created = HTTPStatus(code: 201, reason: "Created")
    public static let noContent = HTTPStatus(code: 204, reason: "No Content")
    public static let badRequest = HTTPStatus(code: 400, reason: "Bad Request")
    public static let notFound = HTTPStatus(code: 404, reason: "Not Found")
    public static let methodNotAllowed = HTTPStatus(code: 405, reason: "Method Not Allowed")
    public static let payloadTooLarge = HTTPStatus(code: 413, reason: "Content Too Large")
    public static let headersTooLarge = HTTPStatus(code: 431, reason: "Request Header Fields Too Large")
    public static let notImplemented = HTTPStatus(code: 501, reason: "Not Implemented")
    public static let versionNotSupported = HTTPStatus(code: 505, reason: "HTTP Version Not Supported")
}

public struct HTTPRequest: Sendable, Equatable {
    public var method: String
    public var path: String
    public var headers: [(name: String, value: String)]
    public var body: [UInt8]
    /// Whether the client wants the connection kept open after the response.
    public var keepAlive: Bool

    public init(method: String, path: String, headers: [(name: String, value: String)] = [], body: [UInt8] = [], keepAlive: Bool = false) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
        self.keepAlive = keepAlive
    }

    public static func == (lhs: HTTPRequest, rhs: HTTPRequest) -> Bool {
        lhs.method == rhs.method && lhs.path == rhs.path && lhs.body == rhs.body && lhs.keepAlive == rhs.keepAlive
            && lhs.headers.elementsEqual(rhs.headers) { $0.name == $1.name && $0.value == $1.value }
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public var status: HTTPStatus
    public var contentType: String?
    public var body: [UInt8]

    public init(status: HTTPStatus, contentType: String? = nil, body: [UInt8] = []) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }

    public static func text(_ status: HTTPStatus, _ text: String) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "text/plain; charset=utf-8", body: Array(text.utf8))
    }

    public static func error(_ status: HTTPStatus) -> HTTPResponse {
        .text(status, status.reason.lowercased())
    }

    /// The full HTTP/1.1 wire representation of this response.
    /// - Parameter includeBody: `false` for responses to `HEAD`, which carry headers only.
    public func serialized(keepAlive: Bool, includeBody: Bool = true) -> Data {
        var head = "HTTP/1.1 \(status.code) \(status.reason)\r\n"
        if let contentType {
            head += "Content-Type: \(contentType)\r\n"
        }
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: \(keepAlive ? "keep-alive" : "close")\r\n\r\n"

        var data = Data(capacity: head.utf8.count + body.count)
        data.append(contentsOf: head.utf8)
        if includeBody {
            data.append(contentsOf: body)
        }
        return data
    }
}
