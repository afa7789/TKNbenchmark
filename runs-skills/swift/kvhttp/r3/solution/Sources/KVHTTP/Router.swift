import Foundation

/// Maps requests onto the key-value store. Contains no networking code.
public struct Router: Sendable {
    public static let maxValueSize = 1 << 20
    static let maxKeyLength = 64

    private let store: KVStore

    public init(store: KVStore) {
        self.store = store
    }

    public func respond(to request: HTTPRequest) -> HTTPResponse {
        let path = request.path
        switch path {
        case "/health":
            guard request.method == "GET" else { return .error(.methodNotAllowed) }
            return .text(.ok, "ok")

        case "/kv":
            guard request.method == "GET" else { return .error(.methodNotAllowed) }
            return listKeys()

        case _ where path.hasPrefix("/kv/"):
            let key = path.dropFirst("/kv/".count)
            guard Self.isValidKey(key) else { return .text(.badRequest, "invalid key") }
            return keyRoute(method: request.method, key: String(key), body: request.body)

        default:
            return .error(.notFound)
        }
    }

    private func keyRoute(method: String, key: String, body: [UInt8]) -> HTTPResponse {
        switch method {
        case "GET":
            guard let value = store.get(key) else { return .error(.notFound) }
            return HTTPResponse(status: .ok, contentType: "application/octet-stream", body: value)
        case "PUT":
            guard body.count <= Self.maxValueSize else { return .error(.payloadTooLarge) }
            return switch store.put(key, value: body) {
            case .created: HTTPResponse(status: .created)
            case .replaced: HTTPResponse(status: .ok)
            }
        case "DELETE":
            return store.delete(key) ? HTTPResponse(status: .noContent) : .error(.notFound)
        default:
            return .error(.methodNotAllowed)
        }
    }

    private func listKeys() -> HTTPResponse {
        let keys = store.sortedKeys()
        // Encoding an array of strings cannot fail.
        let json = (try? JSONEncoder().encode(keys)) ?? Data("[]".utf8)
        return HTTPResponse(status: .ok, contentType: "application/json", body: Array(json))
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
}
