//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import A2uiSampleAgent
import Foundation
import GenUI

/// Command line options of the sample server.
struct ServerOptions {
    /// The port to listen on.
    var port: UInt16 = 10002

    /// The host name advertised in the agent card.
    var host = "localhost"

    /// Parses options from the process arguments.
    /// Supports `--port` and `--host`.
    static func parse(_ arguments: [String]) -> ServerOptions {
        var options = ServerOptions()
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--port", "-p":
                if index + 1 < arguments.count, let port = UInt16(arguments[index + 1]) {
                    options.port = port
                    index += 1
                }
            case "--host":
                if index + 1 < arguments.count {
                    options.host = arguments[index + 1]
                    index += 1
                }
            case "--help", "-h":
                print(
                    """
                    A2UI restaurant sample agent.

                    Usage: swift run a2ui-sample-server [--port 10002] [--host localhost]
                    """
                )
                exit(0)
            default:
                break
            }
            index += 1
        }
        return options
    }
}

let options = ServerOptions.parse(Array(CommandLine.arguments.dropFirst()))
let serviceUrl = "http://\(options.host):\(options.port)/"

let agent: RestaurantAgent
do {
    agent = try RestaurantAgent()
} catch {
    FileHandle.standardError.write(Data("Could not load the sample data: \(error)\n".utf8))
    exit(1)
}

let service = A2AAgentService(agent: agent, serviceUrl: serviceUrl)

let server: HttpServer
do {
    server = try HttpServer(port: options.port) { request in
        switch (request.method, request.path) {
        case ("OPTIONS", _):
            return .text("", status: 204)
        case ("GET", "/.well-known/agent-card.json"), ("GET", "/.well-known/agent.json"):
            return .json(service.agentCard())
        case ("GET", "/health"):
            return .json(["status": "ok"] as JsonMap)
        case ("POST", _):
            guard let json = try? JSONSerialization.jsonObject(with: request.body) as? JsonMap else {
                return .text("Expected a JSON-RPC request body.", status: 400)
            }
            switch service.handle(request: json) {
            case let .stream(events):
                return .eventStream(events)
            case let .single(response):
                return .json(response)
            case let .failure(response):
                return .json(response)
            }
        default:
            return .text("Not found", status: 404)
        }
    }
    try server.start()
} catch {
    FileHandle.standardError.write(Data("Could not start the server: \(error)\n".utf8))
    exit(1)
}

print(
    """
    A2UI \(A2uiProtocol.version) restaurant sample agent
      Agent card: \(serviceUrl).well-known/agent-card.json
      JSON-RPC:   \(serviceUrl)
      Catalog:    \(basicCatalogId)

    Point the GenUISample app at \(serviceUrl) and ask for something like
    "Top 5 Chinese restaurants in New York".

    Press Ctrl+C to stop.
    """
)

signal(SIGINT) { _ in
    print("\nStopped.")
    exit(0)
}

dispatchMain()
