import Foundation
import Testing
@testable import KVServer

@Suite struct RouterTests {
    let router = Router(store: KVStore())

    private func send(_ method: String, _ path: String, _ body: String = "") -> HTTPResponse {
        router.handle(HTTPRequest(method: method, target: path, body: Data(body.utf8)))
    }

    @Test func health() {
        let response = send("GET", "/health")
        #expect(response.status == 200)
        #expect(response.body == Data("ok".utf8))
        #expect(send("POST", "/health").status == 405)
    }

    @Test func crud() {
        #expect(send("PUT", "/kv/a", "x").status == 201)
        #expect(send("PUT", "/kv/a", "y").status == 200)
        #expect(send("GET", "/kv/a").body == Data("y".utf8))
        #expect(send("DELETE", "/kv/a").status == 204)
        #expect(send("DELETE", "/kv/a").status == 404)
        #expect(send("GET", "/kv/a").status == 404)
    }

    @Test func listIsSortedJSON() {
        for key in ["b", "A", "a", "_"] { _ = send("PUT", "/kv/\(key)") }
        let response = send("GET", "/kv")
        #expect(response.body == Data(#"["A","_","a","b"]"#.utf8))
        #expect(response.headers.contains { $0 == ("Content-Type", "application/json") })
    }

    @Test(arguments: ["/kv/", "/kv/a/b", "/kv/bad.key", "/kv/" + String(repeating: "k", count: 65), "/kv/%41", "/kv/é"])
    func invalidKeys(path: String) {
        #expect(send("GET", path).status == 400)
    }

    @Test func otherErrors() {
        #expect(send("GET", "/nope").status == 404)
        #expect(send("PATCH", "/kv/a").status == 405)
        #expect(send("POST", "/kv").status == 405)
        #expect(send("GET", "/kv/" + String(repeating: "k", count: 64)).status == 404)
    }
}

@Suite struct RequestParserTests {
    @Test func parsesPipelinedRequestsAcrossChunks() throws {
        var parser = RequestParser(maxBodyBytes: 1024)
        let wire = "PUT /kv/a HTTP/1.1\r\nContent-Length: 5\r\n\r\nhelloGET /health HTTP/1.1\r\nConnection: close\r\n\r\n"
        for byte in wire.utf8 { parser.append([byte]) }
        let first = try #require(try parser.next())
        #expect(first.method == "PUT" && first.target == "/kv/a" && first.body == Data("hello".utf8))
        #expect(first.keepAlive)
        let second = try #require(try parser.next())
        #expect(second.target == "/health" && !second.keepAlive)
        #expect(try parser.next() == nil)
    }

    @Test func rejectsOversizedBody() {
        var parser = RequestParser(maxBodyBytes: 4)
        parser.append(Array("PUT /kv/a HTTP/1.1\r\nContent-Length: 5\r\n\r\n".utf8))
        #expect(throws: HTTPParseError.bodyTooLarge) { try parser.next() }
    }

    @Test(arguments: ["garbage\r\n\r\n", "GET /\r\n\r\n", "GET / HTTP/1.1\r\nbad header\r\n\r\n", "GET / HTTP/1.1\r\nContent-Length: -1\r\n\r\n"])
    func rejectsMalformed(wire: String) {
        var parser = RequestParser(maxBodyBytes: 4)
        parser.append(Array(wire.utf8))
        #expect(throws: HTTPParseError.malformed) { try parser.next() }
    }
}
