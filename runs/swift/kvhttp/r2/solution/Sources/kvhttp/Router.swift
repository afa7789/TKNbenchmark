/// Maps requests onto store operations. Free of any I/O.
struct Router: Sendable {
    static let maxValueSize = 1 << 20
    static let maxKeyLength = 64

    let store: KeyValueStore

    enum Route: Equatable {
        case health
        case list
        case item(key: String)
        case invalidKey
        case notFound
    }

    static func route(for path: String) -> Route {
        switch path {
        case "/health":
            return .health
        case "/kv":
            return .list
        default:
            let prefix = "/kv/"
            guard path.hasPrefix(prefix) else { return .notFound }
            let key = String(path.dropFirst(prefix.count))
            return isValidKey(key) ? .item(key: key) : .invalidKey
        }
    }

    /// `[A-Za-z0-9_-]{1,64}`
    static func isValidKey(_ key: String) -> Bool {
        let bytes = key.utf8
        guard (1...maxKeyLength).contains(bytes.count) else { return false }
        return bytes.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "_"), UInt8(ascii: "-"):
                true
            default:
                false
            }
        }
    }

    func handle(_ request: HTTPRequest) -> HTTPResponse {
        switch Self.route(for: request.path) {
        case .notFound:
            return HTTPResponse(status: 404)
        case .invalidKey:
            return HTTPResponse(status: 400)
        case .health:
            guard request.method == "GET" else { return HTTPResponse(status: 405) }
            return HTTPResponse(status: 200, contentType: "text/plain; charset=utf-8", text: "ok")
        case .list:
            guard request.method == "GET" else { return HTTPResponse(status: 405) }
            return HTTPResponse(status: 200, contentType: "application/json", text: Self.jsonArray(store.sortedKeys()))
        case .item(let key):
            switch request.method {
            case "GET":
                guard let value = store.get(key) else { return HTTPResponse(status: 404) }
                return HTTPResponse(status: 200, contentType: "application/octet-stream", body: value)
            case "PUT":
                guard request.body.count <= Self.maxValueSize else { return HTTPResponse(status: 413) }
                return HTTPResponse(status: store.put(key, value: request.body) ? 201 : 200)
            case "DELETE":
                return HTTPResponse(status: store.delete(key) ? 204 : 404)
            default:
                return HTTPResponse(status: 405)
            }
        }
    }

    /// Keys are restricted to `[A-Za-z0-9_-]`, so no JSON escaping is required.
    private static func jsonArray(_ keys: [String]) -> String {
        "[" + keys.map { "\"\($0)\"" }.joined(separator: ",") + "]"
    }
}
