/// Maps requests onto store operations. Contains no I/O.
struct Router: Sendable {
    static let maxKeyLength = 64

    let store: KeyValueStore

    func handle(_ request: HTTPRequest) -> HTTPResponse {
        let path = request.path
        let method = request.method

        switch path {
        case "/health":
            guard method == "GET" else { return HTTPResponse(status: .methodNotAllowed) }
            return HTTPResponse(status: .ok, text: "ok")

        case "/kv":
            guard method == "GET" else { return HTTPResponse(status: .methodNotAllowed) }
            return listKeys()

        case let p where p.hasPrefix("/kv/"):
            let key = String(p.dropFirst("/kv/".count))
            guard Self.isValidKey(key) else { return HTTPResponse(status: .badRequest) }
            return handleKey(method: method, key: key, body: request.body)

        default:
            return HTTPResponse(status: .notFound)
        }
    }

    /// A key matches `[A-Za-z0-9_-]{1,64}`.
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

    private func handleKey(method: String, key: String, body: [UInt8]) -> HTTPResponse {
        switch method {
        case "GET":
            guard let value = store.get(key) else { return HTTPResponse(status: .notFound) }
            return HTTPResponse(status: .ok, contentType: "application/octet-stream", body: value)

        case "PUT":
            switch store.put(key, value: body) {
            case .created: return HTTPResponse(status: .created)
            case .replaced: return HTTPResponse(status: .ok)
            }

        case "DELETE":
            return HTTPResponse(status: store.delete(key) ? .noContent : .notFound)

        default:
            return HTTPResponse(status: .methodNotAllowed)
        }
    }

    private func listKeys() -> HTTPResponse {
        // Valid keys never contain characters that need JSON escaping.
        let json = "[" + store.sortedKeys().map { "\"\($0)\"" }.joined(separator: ",") + "]"
        return HTTPResponse(status: .ok, contentType: "application/json", body: Array(json.utf8))
    }
}
