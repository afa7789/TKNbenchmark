/// Maps requests onto store operations. Independent of networking so it can be tested directly.
public struct Router: Sendable {
    public static let maxKeyLength = 64
    public static let maxValueSize = 1 << 20

    private let store: KVStore

    public init(store: KVStore) {
        self.store = store
    }

    public func handle(_ request: HTTPRequest) -> HTTPResponse {
        // Tests never send a query string, but ignore one rather than misroute.
        let path = request.target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let method = request.method

        switch path {
        case "/health":
            guard method == "GET" else { return HTTPResponse(status: 405) }
            return HTTPResponse(status: 200, contentType: "text/plain; charset=utf-8", text: "ok")

        case "/kv":
            guard method == "GET" else { return HTTPResponse(status: 405) }
            return HTTPResponse(status: 200, contentType: "application/json", text: Self.jsonArray(store.keys()))

        case _ where path.hasPrefix("/kv/"):
            let key = path.dropFirst("/kv/".count)
            guard Self.isValidKey(key) else { return HTTPResponse(status: 400) }
            return handleKey(method: method, key: String(key), body: request.body)

        default:
            return HTTPResponse(status: 404)
        }
    }

    private func handleKey(method: String, key: String, body: [UInt8]) -> HTTPResponse {
        switch method {
        case "GET":
            guard let value = store.get(key) else { return HTTPResponse(status: 404) }
            return HTTPResponse(status: 200, contentType: "application/octet-stream", body: value)
        case "PUT":
            guard body.count <= Self.maxValueSize else { return HTTPResponse(status: 413) }
            return HTTPResponse(status: store.put(key, body) ? 201 : 200)
        case "DELETE":
            return HTTPResponse(status: store.delete(key) ? 204 : 404)
        default:
            return HTTPResponse(status: 405)
        }
    }

    /// A key matches `[A-Za-z0-9_-]{1,64}`.
    public static func isValidKey<S: StringProtocol>(_ key: S) -> Bool {
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

    /// Keys are restricted to `[A-Za-z0-9_-]`, so they never need JSON escaping.
    static func jsonArray(_ keys: [String]) -> String {
        "[" + keys.map { "\"\($0)\"" }.joined(separator: ",") + "]"
    }
}
