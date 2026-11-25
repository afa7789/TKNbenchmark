import Foundation
import Network

/// HTTP/1.1 front end for ``Router`` built on Network.framework.
public final class Server: Sendable {
    public enum StartError: Error {
        case invalidPort(Int)
    }

    private let listener: NWListener
    private let router: Router
    private let queue = DispatchQueue(label: "kvhttp.listener")

    public init(host: String = "127.0.0.1", port: Int, store: KVStore = KVStore()) throws {
        guard let rawPort = UInt16(exactly: port), let endpointPort = NWEndpoint.Port(rawValue: rawPort), rawPort != 0 else {
            throw StartError.invalidPort(port)
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: endpointPort)
        listener = try NWListener(using: parameters)
        listener.newConnectionLimit = NWListener.InfiniteConnectionLimit
        router = Router(store: store)
    }

    /// Starts accepting connections. `onFailure` is called if the listener fails (e.g. port in use).
    public func start(onFailure: @escaping @Sendable (NWError) -> Void) {
        listener.newConnectionHandler = { [router] connection in
            HTTPConnection(connection: connection, router: router).start()
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                onFailure(error)
            }
        }
        listener.start(queue: queue)
    }

    public func stop() {
        listener.cancel()
    }
}

/// Drives one client connection: read, parse, respond, repeat while keep-alive.
/// Parser state is threaded through the callbacks, so the type itself is immutable.
private struct HTTPConnection: Sendable {
    let connection: NWConnection
    let router: Router

    func start() {
        connection.stateUpdateHandler = { [connection] state in
            switch state {
            case .failed, .waiting:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue(label: "kvhttp.connection"))
        receive(into: HTTPRequestParser(maxBodyBytes: Router.maxValueSize))
    }

    private func receive(into parser: HTTPRequestParser) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 18) { data, _, isComplete, error in
            var parser = parser
            if let data {
                parser.append(data)
            }
            process(parser, endOfInput: isComplete || error != nil)
        }
    }

    private func process(_ parser: HTTPRequestParser, endOfInput: Bool) {
        var parser = parser
        switch parser.next() {
        case .incomplete:
            if endOfInput {
                connection.cancel()
            } else {
                receive(into: parser)
            }

        case .request(let request):
            let response = router.respond(to: request)
            let keepAlive = request.keepAlive && !endOfInput
            let remaining = parser
            send(response, keepAlive: keepAlive, includeBody: request.method != "HEAD") {
                if keepAlive {
                    process(remaining, endOfInput: false)
                }
            }

        case .failure(let status):
            send(.error(status), keepAlive: false) {}
        }
    }

    /// Sends the response; closes the connection afterwards unless `keepAlive`.
    private func send(
        _ response: HTTPResponse,
        keepAlive: Bool,
        includeBody: Bool = true,
        then next: @escaping @Sendable () -> Void
    ) {
        connection.send(
            content: response.serialized(keepAlive: keepAlive, includeBody: includeBody),
            contentContext: keepAlive ? .defaultMessage : .finalMessage,
            isComplete: true,
            completion: .contentProcessed { [connection] error in
                if error == nil, keepAlive {
                    next()
                } else {
                    connection.cancel()
                }
            }
        )
    }
}
