import Foundation

/// Maps requests onto the key-value store. Independent of networking so it can be unit tested.
public struct Router: Sendable {
    /// Largest accepted value, in bytes.
    public static let maxValueSize = 1 << 20
    static let maxKeyLength = 64
    private static let keyPrefix = "/kv/"

    private let store: KVStore

    public init(store: KVStore) {
        self.store = store
    }

    public func handle(_ request: HTTPRequest) -> HTTPResponse {
        let path = request.path
        let method = request.method
        if path == "/health" {
            guard method == "GET" else { return Self.methodNotAllowed(allow: "GET") }
            return HTTPResponse(status: 200, headers: [("Content-Type", "text/plain; charset=utf-8")], body: Data("ok".utf8))
        }
        if path == "/kv" {
            guard method == "GET" else { return Self.methodNotAllowed(allow: "GET") }
            return listKeys()
        }
        guard path.hasPrefix(Self.keyPrefix) else {
            return HTTPResponse(status: 404)
        }
        let key = path.dropFirst(Self.keyPrefix.count)
        guard Self.isValidKey(key) else {
            return HTTPResponse(status: 400)
        }
        let name = String(key)
        switch method {
        case "GET":
            guard let value = store.get(name) else { return HTTPResponse(status: 404) }
            return HTTPResponse(status: 200, headers: [("Content-Type", "application/octet-stream")], body: value)
        case "PUT":
            guard request.body.count <= Self.maxValueSize else { return HTTPResponse(status: 413) }
            return HTTPResponse(status: store.put(name, request.body) ? 201 : 200)
        case "DELETE":
            return HTTPResponse(status: store.delete(name) ? 204 : 404)
        default:
            return Self.methodNotAllowed(allow: "GET, PUT, DELETE")
        }
    }

    /// A key matches `[A-Za-z0-9_-]{1,64}`.
    static func isValidKey(_ key: some StringProtocol) -> Bool {
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

    private func listKeys() -> HTTPResponse {
        // Valid keys contain only [A-Za-z0-9_-], so they need no JSON escaping.
        let json = "[" + store.keys().map { "\"\($0)\"" }.joined(separator: ",") + "]"
        return HTTPResponse(status: 200, headers: [("Content-Type", "application/json")], body: Data(json.utf8))
    }

    private static func methodNotAllowed(allow: String) -> HTTPResponse {
        HTTPResponse(status: 405, headers: [("Allow", allow)])
    }
}
