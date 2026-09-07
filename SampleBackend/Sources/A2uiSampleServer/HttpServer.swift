//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import Network

/// A parsed HTTP request.
struct HttpRequest {
    /// The request method, for example `GET`.
    let method: String

    /// The request path, without the query string.
    let path: String

    /// The request headers, with lowercased names.
    let headers: [String: String]

    /// The request body.
    let body: Data
}

/// The response a handler returns.
enum HttpResponse {
    /// A JSON body with a 200 status.
    case json(Any)

    /// A sequence of server-sent events, streamed then closed.
    case eventStream([Any])

    /// A plain text body with an explicit status.
    case text(String, status: Int)
}

/// A minimal HTTP/1.1 server for the sample backend.
///
/// The sample deliberately avoids a server framework so that the backend can be
/// started with `swift run` and no package resolution beyond this repository.
/// It handles exactly what the A2A binding needs: JSON request bodies, JSON
/// responses, and server-sent events.
final class HttpServer {
    private let port: NWEndpoint.Port
    private let handler: (HttpRequest) -> HttpResponse
    private let queue = DispatchQueue(label: "a2ui.sample.server")
    private var listener: NWListener?

    /// Creates a server on a port.
    /// The handler runs on the server's queue.
    init(port: UInt16, handler: @escaping (HttpRequest) -> HttpResponse) throws {
        guard let port = NWEndpoint.Port(rawValue: port) else {
            throw HttpServerError.invalidPort(port)
        }
        self.port = port
        self.handler = handler
    }

    /// Starts listening for connections.
    /// Throws when the port cannot be bound.
    func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [port] state in
            guard case let .failed(error) = state else { return }
            var message = "Could not listen on port \(port): \(error)\n"
            if case .posix(.EADDRINUSE) = error {
                message += "Another process is already using it. "
                message += "Stop it, or start this one with --port <other port>.\n"
            }
            FileHandle.standardError.write(Data(message.utf8))
            exit(1)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    /// Stops listening and releases the port.
    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                FileHandle.standardError.write(Data("Connection error: \(error)\n".utf8))
                connection.cancel()
                return
            }

            var buffer = buffer
            if let data {
                buffer.append(data)
            }

            switch HttpRequestParser.parse(buffer) {
            case let .complete(request):
                self.respond(to: request, on: connection)
            case .incomplete:
                if isComplete {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            case let .invalid(reason):
                self.write(
                    HttpResponseEncoder.encode(.text(reason, status: 400)),
                    on: connection,
                    thenClose: true
                )
            }
        }
    }

    private func respond(to request: HttpRequest, on connection: NWConnection) {
        let response = handler(request)
        write(HttpResponseEncoder.encode(response), on: connection, thenClose: true)
    }

    private func write(_ data: Data, on connection: NWConnection, thenClose: Bool) {
        connection.send(
            content: data,
            completion: .contentProcessed { _ in
                if thenClose {
                    connection.cancel()
                }
            }
        )
    }
}

/// Failures raised while starting the server.
enum HttpServerError: Error, CustomStringConvertible {
    /// The requested port is outside the valid range.
    case invalidPort(UInt16)

    var description: String {
        switch self {
        case let .invalidPort(port):
            return "\(port) is not a valid TCP port."
        }
    }
}

/// Parses HTTP/1.1 requests out of a byte buffer.
enum HttpRequestParser {
    /// The outcome of a parse attempt.
    enum Result {
        /// A complete request was parsed.
        case complete(HttpRequest)

        /// More bytes are needed.
        case incomplete

        /// The bytes are not a valid request.
        case invalid(String)
    }

    private static let headerTerminator = Data("\r\n\r\n".utf8)

    /// Parses a request, reporting whether more bytes are needed.
    /// Bodies are matched against the `Content-Length` header.
    static func parse(_ buffer: Data) -> Result {
        guard let headerEnd = buffer.range(of: headerTerminator) else {
            return .incomplete
        }
        guard let headerText = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return .invalid("Headers are not valid UTF-8.")
        }

        var lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return .invalid("Missing request line.")
        }
        lines.removeFirst()

        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else {
            return .invalid("Malformed request line.")
        }
        let method = String(requestParts[0])
        let target = String(requestParts[1])
        let path = target.components(separatedBy: "?").first ?? target

        var headers: [String: String] = [:]
        for line in lines where line.contains(":") {
            let pieces = line.split(separator: ":", maxSplits: 1)
            guard pieces.count == 2 else { continue }
            headers[pieces[0].lowercased()] = pieces[1].trimmingCharacters(in: .whitespaces)
        }

        let expectedLength = Int(headers["content-length"] ?? "0") ?? 0
        let body = buffer[headerEnd.upperBound...]
        guard body.count >= expectedLength else {
            return .incomplete
        }

        return .complete(
            HttpRequest(
                method: method,
                path: path,
                headers: headers,
                body: Data(body.prefix(expectedLength))
            )
        )
    }
}

/// Serializes responses into HTTP/1.1 byte streams.
enum HttpResponseEncoder {
    /// Encodes a response, including its status line and headers.
    static func encode(_ response: HttpResponse) -> Data {
        switch response {
        case let .json(payload):
            let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
            return message(status: 200, reason: "OK", contentType: "application/json", body: body)
        case let .eventStream(events):
            var body = Data()
            for event in events {
                let json = (try? JSONSerialization.data(withJSONObject: event)) ?? Data("{}".utf8)
                body.append(Data("data: ".utf8))
                body.append(json)
                body.append(Data("\n\n".utf8))
            }
            return message(status: 200, reason: "OK", contentType: "text/event-stream", body: body)
        case let .text(text, status):
            return message(
                status: status,
                reason: status == 200 ? "OK" : "Error",
                contentType: "text/plain; charset=utf-8",
                body: Data(text.utf8)
            )
        }
    }

    private static func message(status: Int, reason: String, contentType: String, body: Data) -> Data {
        var headers = "HTTP/1.1 \(status) \(reason)\r\n"
        headers += "Content-Type: \(contentType)\r\n"
        headers += "Content-Length: \(body.count)\r\n"
        headers += "Access-Control-Allow-Origin: *\r\n"
        headers += "Access-Control-Allow-Headers: *\r\n"
        headers += "Cache-Control: no-store\r\n"
        headers += "Connection: close\r\n\r\n"

        var data = Data(headers.utf8)
        data.append(body)
        return data
    }
}
