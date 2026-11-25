import Foundation
import Network

/// HTTP/1.1 key-value server built on Network.framework.
public struct Server: Sendable {
    public let host: String
    public let port: UInt16
    /// Connections idle for longer than this are closed.
    public var idleTimeout: Duration = .seconds(30)

    private let router: Router

    public init(host: String = "127.0.0.1", port: UInt16, store: KVStore = KVStore()) {
        self.host = host
        self.port = port
        self.router = Router(store: store)
    }

    /// Listens and serves connections until the listener fails or the task is cancelled.
    public func run() async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw ServerError.invalidPort(port) }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: nwPort)
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
        }

        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "kvhttp.network", attributes: .concurrent)
        let (connections, continuation) = AsyncThrowingStream.makeStream(of: NWConnection.self)
        listener.newConnectionHandler = { continuation.yield($0) }
        listener.stateUpdateHandler = { state in
            switch state {
            case .failed(let error): continuation.finish(throwing: error)
            case .cancelled: continuation.finish()
            default: break
            }
        }
        continuation.onTermination = { _ in listener.cancel() }
        listener.start(queue: queue)

        let router = self.router
        let idleTimeout = self.idleTimeout
        try await withThrowingDiscardingTaskGroup { group in
            for try await connection in connections {
                group.addTask {
                    await HTTPConnection(connection: connection, router: router, idleTimeout: idleTimeout)
                        .serve(on: queue)
                }
            }
        }
    }
}

public enum ServerError: Error, CustomStringConvertible {
    case invalidPort(UInt16)

    public var description: String {
        switch self {
        case .invalidPort(let port): "invalid port \(port)"
        }
    }
}

/// Serves HTTP requests on one accepted connection.
private struct HTTPConnection {
    private static let receiveChunkSize = 64 * 1024

    let connection: NWConnection
    let router: Router
    let idleTimeout: Duration

    func serve(on queue: DispatchQueue) async {
        connection.start(queue: queue)
        defer { connection.cancel() }

        var parser = RequestParser(maxBodyBytes: Router.maxValueSize)
        do {
            while true {
                let request: HTTPRequest
                do {
                    guard let next = try await nextRequest(&parser) else { return }
                    request = next
                } catch let error as HTTPParseError {
                    let response = HTTPResponse(status: error.status)
                    try await send(response.serialized(keepAlive: false))
                    return
                }
                let keepAlive = request.keepAlive
                try await send(router.handle(request).serialized(keepAlive: keepAlive))
                guard keepAlive else { return }
            }
        } catch {
            // The peer went away or timed out; the deferred cancel releases the connection.
        }
    }

    /// Reads until a full request is parsed. Returns `nil` on a clean end of stream between requests.
    private func nextRequest(_ parser: inout RequestParser) async throws -> HTTPRequest? {
        while true {
            if let request = try parser.next() { return request }
            let (data, isComplete) = try await receive()
            if let data { parser.append(data) }
            if isComplete {
                if let request = try parser.next() { return request }
                if parser.hasBufferedBytes { throw HTTPParseError.malformed }
                return nil
            }
        }
    }

    private func receive() async throws -> (Data?, Bool) {
        let connection = self.connection
        let watchdog = Task {
            try await Task.sleep(for: idleTimeout)
            connection.cancel()
        }
        defer { watchdog.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: Self.receiveChunkSize) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data, isComplete))
                }
            }
        }
    }

    private func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: data, isComplete: false, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}
