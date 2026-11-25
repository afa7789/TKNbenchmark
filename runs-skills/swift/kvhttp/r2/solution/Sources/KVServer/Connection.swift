#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Serves HTTP/1.1 requests on one client connection until it closes.
struct Connection: Sendable {
    static let ioTimeoutSeconds = 30
    private static let readChunkSize = 64 * 1024
    private static let continueResponse = Array("HTTP/1.1 100 Continue\r\n\r\n".utf8)

    let socket: StreamSocket
    let router: Router

    func serve() {
        defer { socket.close() }
        #if canImport(Darwin)
        socket.setOption(SOL_SOCKET, SO_NOSIGPIPE, 1)
        #endif
        socket.setOption(Int32(IPPROTO_TCP), TCP_NODELAY, 1)
        socket.setTimeout(SO_RCVTIMEO, seconds: Self.ioTimeoutSeconds)
        socket.setTimeout(SO_SNDTIMEO, seconds: Self.ioTimeoutSeconds)

        var buffer: [UInt8] = []
        var scratch = [UInt8](repeating: 0, count: Self.readChunkSize)

        while true {
            // Read until the blank line that ends the head.
            var scanned = 0
            var headEnd: Int?
            while headEnd == nil {
                headEnd = RequestParser.headEnd(in: buffer, from: scanned - 3)
                if headEnd != nil { break }
                scanned = buffer.count
                if buffer.count > RequestParser.maxHeadSize {
                    sendError(.headersTooLarge)
                    return
                }
                guard socket.read(appendingTo: &buffer, scratch: &scratch) else { return }
            }
            guard let headEnd else { return }

            var head: RequestHead
            do {
                head = try RequestParser.parseHead(buffer[..<(headEnd - 4)], maxBodySize: Router.maxValueSize)
            } catch {
                sendError(error)
                return
            }

            // Read the body.
            let requestEnd = headEnd + head.contentLength
            if buffer.count < requestEnd {
                if head.request.header("expect")?.lowercased() == "100-continue" {
                    guard socket.write(Self.continueResponse) else { return }
                }
                buffer.reserveCapacity(requestEnd)
                while buffer.count < requestEnd {
                    guard socket.read(appendingTo: &buffer, scratch: &scratch) else { return }
                }
            }
            head.request.body = Array(buffer[headEnd..<requestEnd])
            buffer.removeSubrange(..<requestEnd)

            let keepAlive = head.request.isKeepAlive
            guard write(router.handle(head.request), keepAlive: keepAlive), keepAlive else { return }
        }
    }

    @discardableResult
    private func write(_ response: HTTPResponse, keepAlive: Bool) -> Bool {
        socket.write(response.serializedHead(keepAlive: keepAlive))
            && (response.body.isEmpty || socket.write(response.body))
    }

    private func sendError(_ error: HTTPParseError) {
        write(HTTPResponse(status: error.status), keepAlive: false)
    }
}
