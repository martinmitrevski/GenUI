//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import GenUI

/// What the transport should send back for one JSON-RPC request.
public enum A2AServiceResult {
    /// A sequence of server-sent events, for `message/stream`.
    case stream([JsonMap])

    /// A single JSON-RPC response, for `message/send`.
    case single(JsonMap)

    /// A JSON-RPC error response.
    case failure(JsonMap)
}

/// Serves an A2UI agent over the A2A protocol.
///
/// This type contains everything about the A2A binding except the socket: it
/// builds the agent card, decodes incoming `message/send` and `message/stream`
/// requests into ``AgentRequest`` values, and encodes the agent's answer as A2A
/// messages with A2UI data parts. Keeping it transport free makes the whole
/// exchange unit testable.
public struct A2AAgentService {
    /// The agent that produces surfaces.
    public let agent: RestaurantAgent

    /// The URL clients use to reach this service.
    public let serviceUrl: String

    private let idProvider: () -> String
    private let taskStore = TaskStore()

    /// Creates a service for an agent.
    /// Inject `idProvider` to make ids deterministic in tests.
    public init(
        agent: RestaurantAgent,
        serviceUrl: String,
        idProvider: @escaping () -> String = { UUID().uuidString }
    ) {
        self.agent = agent
        self.serviceUrl = serviceUrl
        self.idProvider = idProvider
    }

    /// The agent card served from `/.well-known/agent-card.json`.
    ///
    /// The card advertises the A2UI extension so renderers know which catalogs
    /// the agent can generate and whether to attach their capabilities.
    public func agentCard() -> JsonMap {
        [
            "protocolVersion": "0.3.0",
            "name": RestaurantAgent.name,
            "description": RestaurantAgent.description,
            "version": RestaurantAgent.version,
            "url": serviceUrl,
            "preferredTransport": "JSONRPC",
            "defaultInputModes": ["text/plain", A2uiProtocol.mimeType],
            "defaultOutputModes": ["text/plain", A2uiProtocol.mimeType],
            "capabilities": [
                "streaming": true,
                "pushNotifications": false,
                "extensions": [
                    [
                        "uri": A2uiProtocol.a2aExtensionUri,
                        "description": "Renders agent-driven UI with A2UI v1.0.",
                        "required": false,
                        "params": agent.capabilities.toJson()[A2uiProtocol.version] ?? [:]
                    ] as JsonMap
                ]
            ] as JsonMap,
            "skills": [
                [
                    "id": "order_food",
                    "name": "Find restaurants and order food",
                    "description": "Searches restaurants and renders an interactive order form.",
                    "tags": ["food", "a2ui"],
                    "examples": [
                        "Top 5 Chinese restaurants in New York",
                        "Find sushi in San Francisco"
                    ]
                ] as JsonMap
            ]
        ]
    }

    /// Handles one JSON-RPC request.
    /// Unknown methods produce a JSON-RPC "method not found" error.
    public func handle(request: JsonMap) -> A2AServiceResult {
        let id = request["id"] ?? NSNull()
        guard let method = request["method"] as? String else {
            return .failure(Self.errorResponse(id: id, code: -32600, message: "Missing 'method'."))
        }
        guard let params = Json.map(request["params"]), let message = Json.map(params["message"]) else {
            return .failure(Self.errorResponse(id: id, code: -32602, message: "Missing 'params.message'."))
        }

        let agentRequest = Self.decode(message: message, fallbackContextId: idProvider())
        let response = agent.respond(to: agentRequest)
        let taskId = taskStore.taskId(for: agentRequest.contextId, generator: idProvider)
        let agentMessage = encode(
            response: response,
            contextId: agentRequest.contextId,
            taskId: taskId
        )

        switch method {
        case "message/stream":
            return .stream([
                Self.rpcResponse(
                    id: id,
                    result: [
                        "id": taskId,
                        "contextId": agentRequest.contextId,
                        "kind": "task",
                        "status": ["state": "working"] as JsonMap
                    ]
                ),
                Self.rpcResponse(
                    id: id,
                    result: [
                        "taskId": taskId,
                        "contextId": agentRequest.contextId,
                        "kind": "status-update",
                        "final": true,
                        "end": true,
                        "status": [
                            "state": "input-required",
                            "message": agentMessage
                        ] as JsonMap
                    ]
                )
            ])
        case "message/send":
            return .single(Self.rpcResponse(id: id, result: agentMessage))
        default:
            return .failure(
                Self.errorResponse(id: id, code: -32601, message: "Unsupported method '\(method)'.")
            )
        }
    }

    // MARK: - Decoding

    /// Decodes an incoming A2A message into an agent request.
    ///
    /// Text parts become the prompt, A2UI data parts become renderer messages,
    /// and message metadata carries renderer capabilities and data models.
    public static func decode(message: JsonMap, fallbackContextId: String) -> AgentRequest {
        var text: [String] = []
        var rendererMessages: [RendererMessage] = []

        for part in Json.array(message["parts"]) ?? [] {
            guard let part = Json.map(part) else { continue }
            let kind = (part["kind"] as? String) ?? (part["type"] as? String)
            switch kind {
            case "text":
                if let value = part["text"] as? String, !value.isEmpty {
                    text.append(value)
                }
            case "data":
                rendererMessages.append(contentsOf: decodeRendererMessages(part["data"]))
            default:
                continue
            }
        }

        let metadata = Json.map(message["metadata"]) ?? [:]
        return AgentRequest(
            contextId: (message["contextId"] as? String) ?? fallbackContextId,
            text: text.isEmpty ? nil : text.joined(separator: "\n"),
            rendererMessages: rendererMessages,
            capabilities: Json.map(metadata[A2uiProtocol.rendererCapabilitiesKey])
                .flatMap(RendererCapabilities.fromJson),
            dataModel: Json.map(metadata[A2uiProtocol.rendererDataModelKey])
                .flatMap(RendererDataModel.fromJson)
        )
    }

    private static func decodeRendererMessages(_ data: Any?) -> [RendererMessage] {
        let candidates: JsonArray
        if let array = Json.array(data) {
            candidates = array
        } else if let map = Json.map(data) {
            candidates = Json.array(map["messages"]) ?? [map]
        } else {
            return []
        }

        return candidates.compactMap { candidate in
            guard let json = Json.map(candidate), RendererMessage.isMessage(json) else { return nil }
            do {
                return try RendererMessage.fromJson(json)
            } catch {
                print("[agent] could not decode a renderer message: \(error)")
                return nil
            }
        }
    }

    // MARK: - Encoding

    private func encode(response: AgentResponse, contextId: String, taskId: String) -> JsonMap {
        var parts: JsonArray = []
        if !response.messages.isEmpty {
            parts.append(
                [
                    "kind": "data",
                    "data": response.messages.map { $0.toJson() },
                    "metadata": ["mimeType": A2uiProtocol.mimeType] as JsonMap
                ] as JsonMap
            )
        }
        if let text = response.text, !text.isEmpty {
            parts.append(["kind": "text", "text": text] as JsonMap)
        }
        return [
            "messageId": idProvider(),
            "role": "agent",
            "kind": "message",
            "contextId": contextId,
            "taskId": taskId,
            "parts": parts
        ]
    }

    private static func rpcResponse(id: Any, result: JsonMap) -> JsonMap {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private static func errorResponse(id: Any, code: Int, message: String) -> JsonMap {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message] as JsonMap]
    }

    /// Remembers the task id created for each conversation.
    private final class TaskStore {
        private let lock = NSLock()
        private var tasks: [String: String] = [:]

        func taskId(for contextId: String, generator: () -> String) -> String {
            lock.lock()
            defer { lock.unlock() }
            if let existing = tasks[contextId] { return existing }
            let taskId = generator()
            tasks[contextId] = taskId
            return taskId
        }
    }
}
