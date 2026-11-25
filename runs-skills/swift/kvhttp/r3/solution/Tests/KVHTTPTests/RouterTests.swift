import Testing
@testable import KVHTTP

@Suite struct RouterTests {
    let router = Router(store: KVStore())

    private func call(_ method: String, _ path: String, _ body: String = "") -> HTTPResponse {
        router.respond(to: HTTPRequest(method: method, path: path, body: Array(body.utf8)))
    }

    @Test func health() {
        let response = call("GET", "/health")
        #expect(response.status == .ok)
        #expect(response.body == Array("ok".utf8))
        #expect(call("POST", "/health").status == .methodNotAllowed)
    }

    @Test func crud() {
        #expect(call("PUT", "/kv/a", "hello").status == .created)
        #expect(call("GET", "/kv/a").body == Array("hello".utf8))
        #expect(call("PUT", "/kv/a", "world").status == .ok)
        #expect(call("DELETE", "/kv/a").status == .noContent)
        #expect(call("GET", "/kv/a").status == .notFound)
        #expect(call("DELETE", "/kv/a").status == .notFound)
    }

    @Test func listIsSortedJSON() {
        for key in ["b", "a", "C"] { _ = call("PUT", "/kv/\(key)", "x") }
        let response = call("GET", "/kv")
        #expect(response.contentType == "application/json")
        #expect(response.body == Array(#"["C","a","b"]"#.utf8))
        #expect(call("DELETE", "/kv").status == .methodNotAllowed)
    }

    @Test(arguments: ["/kv/", "/kv/a.b", "/kv/a/b", "/kv/" + String(repeating: "k", count: 65), "/kv/%41", "/kv/é"])
    func invalidKeys(path: String) {
        #expect(call("GET", path).status == .badRequest)
    }

    @Test func maxLengthKeyIsValid() {
        #expect(call("PUT", "/kv/" + String(repeating: "k", count: 64), "v").status == .created)
    }

    @Test func unknownPathsAndMethods() {
        #expect(call("GET", "/nope").status == .notFound)
        #expect(call("GET", "/kvx").status == .notFound)
        #expect(call("PATCH", "/kv/a").status == .methodNotAllowed)
    }
}
