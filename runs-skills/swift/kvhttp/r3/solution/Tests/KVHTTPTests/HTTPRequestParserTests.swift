import Testing
@testable import KVHTTP

@Suite struct HTTPRequestParserTests {
    private func parser(_ text: String, maxBodyBytes: Int = 1024) -> HTTPRequestParser {
        var parser = HTTPRequestParser(maxBodyBytes: maxBodyBytes)
        parser.append(text.utf8)
        return parser
    }

    @Test func parsesRequestWithBodyAcrossChunks() {
        var parser = HTTPRequestParser(maxBodyBytes: 1024)
        parser.append("PUT /kv/a HTTP/1.1\r\nContent-Le".utf8)
        #expect(parser.next() == .incomplete)
        parser.append("ngth: 5\r\nConnection: close\r\n\r\nhel".utf8)
        #expect(parser.next() == .incomplete)
        parser.append("lo".utf8)
        guard case .request(let request) = parser.next() else {
            Issue.record("expected a request")
            return
        }
        #expect(request.method == "PUT")
        #expect(request.path == "/kv/a")
        #expect(request.body == Array("hello".utf8))
        #expect(!request.keepAlive)
    }

    @Test func handlesPipelinedRequests() {
        var parser = parser("GET /a HTTP/1.1\r\n\r\nGET /b HTTP/1.0\r\n\r\n")
        guard case .request(let first) = parser.next(), case .request(let second) = parser.next() else {
            Issue.record("expected two requests")
            return
        }
        #expect(first.path == "/a" && first.keepAlive)
        #expect(second.path == "/b" && !second.keepAlive)
        #expect(parser.next() == .incomplete)
    }

    @Test(arguments: [
        ("garbage\r\n\r\n", HTTPStatus.badRequest),
        ("GET / HTTP/2.0\r\n\r\n", .versionNotSupported),
        ("PUT /a HTTP/1.1\r\nContent-Length: x\r\n\r\n", .badRequest),
        ("PUT /a HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n", .badRequest),
        ("PUT /a HTTP/1.1\r\nContent-Length: 2048\r\n\r\n", .payloadTooLarge),
        ("PUT /a HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n", .notImplemented),
    ])
    func rejectsInvalidRequests(text: String, status: HTTPStatus) {
        var parser = parser(text)
        #expect(parser.next() == .failure(status))
    }
}
