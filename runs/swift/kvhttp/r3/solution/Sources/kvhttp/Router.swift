/// Maps requests onto store operations. Free of I/O.
struct Router {
    static let maxValueSize = 1 << 20

    let store: KeyValueStore

    func handle(_ request: HTTPRequest) -> HTTPResponse {
        // Paths never carry a query string per the spec, but strip one defensively.
        let path = request.target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? request.target
        let method = request.method

        switch path {
        case "/health":
            guard method == "GET" else { return HTTPResponse(405) }
            return HTTPResponse(200, body: Array("ok".utf8), contentType: "text/plain")

        case "/kv":
            guard method == "GET" else { return HTTPResponse(405) }
            return listKeys()

        case let p where p.hasPrefix("/kv/"):
            let key = String(p.dropFirst("/kv/".count))
            guard Self.isValidKey(key) else { return HTTPResponse(400) }
            return handleKey(method: method, key: key, body: request.body)

        default:
            return HTTPResponse(404)
        }
    }

    private func handleKey(method: String, key: String, body: [UInt8]) -> HTTPResponse {
        switch method {
        case "GET":
            guard let value = store.get(key) else { return HTTPResponse(404) }
            return HTTPResponse(200, body: value, contentType: "application/octet-stream")
        case "PUT":
            switch store.put(key, value: body) {
            case .created: return HTTPResponse(201)
            case .replaced: return HTTPResponse(200)
            }
        case "DELETE":
            return store.delete(key) ? HTTPResponse(204) : HTTPResponse(404)
        default:
            return HTTPResponse(405)
        }
    }

    private func listKeys() -> HTTPResponse {
        // Keys are restricted to [A-Za-z0-9_-], so they never need JSON escaping.
        let json = "[" + store.sortedKeys().map { "\"\($0)\"" }.joined(separator: ",") + "]"
        return HTTPResponse(200, body: Array(json.utf8), contentType: "application/json")
    }

    static func isValidKey(_ key: String) -> Bool {
        let bytes = key.utf8
        guard (1...64).contains(bytes.count) else { return false }
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
}
