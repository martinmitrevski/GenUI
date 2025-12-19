//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import Combine

/// Basic metadata describing an A2UI agent.
/// Includes name, description, and version strings.
public struct AgentCard {
    public let name: String
    public let description: String
    public let version: String

    /// Creates an agent card payload.
    /// Use this to surface agent metadata in UIs.
    public init(name: String, description: String, version: String) {
        self.name = name
        self.description = description
        self.version = version
    }
}

/// Connects to an A2UI agent over A2A and streams responses.
/// Translates A2A messages into `A2uiMessage` updates.
public final class A2uiAgentConnector {
    public let url: URL

    private let controller = PassthroughSubject<A2uiMessage, Never>()
    private let errorController = PassthroughSubject<Error, Never>()

    public var client: A2AClientProtocol
    public var taskId: String?
    private var contextIdValue: String?

    public var contextId: String? {
        contextIdValue
    }

    /// Creates a connector for the given server URL.
    /// Optionally inject a custom A2A client and context id.
    public init(url: URL, client: A2AClientProtocol? = nil, contextId: String? = nil) {
        self.url = url
        self.client = client ?? A2AClient(baseUrl: url.absoluteString)
        self.contextIdValue = contextId
    }

    public var stream: AnyPublisher<A2uiMessage, Never> {
        controller.eraseToAnyPublisher()
    }

    public var errorStream: AnyPublisher<Error, Never> {
        errorController.eraseToAnyPublisher()
    }

    /// Fetches the agent card from the A2A client.
    /// Returns the parsed name, description, and version.
    public func getAgentCard() async throws -> AgentCard {
        let card = try await client.getAgentCard()
        return AgentCard(name: card.name, description: card.description, version: card.version)
    }

    /// Sends a chat message to the agent and streams responses.
    /// Returns the final text response when available.
    public func connectAndSend(
        _ chatMessage: ChatMessage,
        clientCapabilities: A2UiClientCapabilities? = nil
    ) async -> String? {
        let parts: [MessagePart]
        if let userMessage = chatMessage as? UserMessage {
            parts = userMessage.parts
        } else if let userMessage = chatMessage as? UserUiInteractionMessage {
            parts = userMessage.parts
        } else {
            parts = []
        }

        var message = A2AMessage()
        message.messageId = UUID().uuidString
        message.role = "user"
        message.parts = parts.map { part in
            switch part {
            case let text as TextPart:
                return A2ATextPart(text: text.text)
            case let data as DataPart:
                return A2ADataPart(data: data.data ?? [:])
            case let image as ImagePart:
                if let url = image.url {
                    let file = A2AFileWithUri(uri: url.absoluteString, mimeType: image.mimeType)
                    return A2AFilePart(file: file)
                }
                let base64Data: String
                if let bytes = image.bytes {
                    base64Data = bytes.base64EncodedString()
                } else if let base64 = image.base64 {
                    base64Data = base64
                } else {
                    genUiLogger.warning("ImagePart has no data (url, bytes, or base64)")
                    return A2ATextPart(text: "[Empty Image]")
                }
                let file = A2AFileWithBytes(bytes: base64Data, mimeType: image.mimeType)
                return A2AFilePart(file: file)
            default:
                genUiLogger.warning("Unknown message part type: \(type(of: part))")
                return A2ATextPart(text: "[Unknown Part]")
            }
        }

        if let taskId {
            message.referenceTaskIds = [taskId]
        }
        if let contextIdValue {
            message.contextId = contextIdValue
        }
        if let clientCapabilities {
            message.metadata = [
                "a2uiClientCapabilities": clientCapabilities.toJson()
            ]
        }

        var payload = A2AMessageSendParams(message: message)
        payload.extensions = ["https://a2ui.org/a2a-extension/a2ui/v0.8"]

        genUiLogger.info("--- OUTGOING REQUEST ---")
        genUiLogger.info("URL: \(url.absoluteString)")
        genUiLogger.info("Method: message/stream")
        if let pretty = prettyJson(payload.toJson()) {
            genUiLogger.info("Payload: \(pretty)")
        }
        genUiLogger.info("----------------------")

        let events = client.sendMessageStream(payload)

        var responseText: String?
        var finalResponse: A2AMessage?

        do {
            for try await event in events {
                if let pretty = prettyJson(event.toJson()) {
                    genUiLogger.info("Received A2A event:\n\(pretty)")
                }

                if event.isError, let errorResponse = event as? A2AJSONRPCErrorResponseSSM {
                    let code = errorResponse.error?.rpcErrorCode
                    let errorMessage = "A2A Error: \(String(describing: code))"
                    genUiLogger.severe(errorMessage)
                    errorController.send(A2AClientError.invalidResponse)
                    continue
                }

                if let response = event as? A2ASendStreamMessageSuccessResponse {
                    let result = response.result
                    if let task = result as? A2ATask {
                        taskId = task.id
                        contextIdValue = task.contextId
                    }

                    let message: A2AMessage?
                    if let task = result as? A2ATask {
                        message = task.status?.message
                    } else if let messageResult = result as? A2AMessage {
                        message = messageResult
                    } else if let update = result as? A2ATaskStatusUpdateEvent {
                        message = update.status?.message
                    } else {
                        message = nil
                    }

                    if let message {
                        finalResponse = message
                        if let pretty = prettyJson(message.toJson()) {
                            genUiLogger.info("Received A2A Message:\n\(pretty)")
                        }
                        for part in message.parts {
                            if let dataPart = part as? A2ADataPart {
                                processA2uiMessages(dataPart.data)
                            }
                        }
                    }
                }
            }
        } catch {
            genUiLogger.severe("Error parsing A2A response: \(error)")
            errorController.send(error)
        }

        if let finalResponse {
            for part in finalResponse.parts {
                if let textPart = part as? A2ATextPart {
                    responseText = textPart.text
                }
            }
        }

        return responseText
    }

    /// Sends a user interaction event to the agent.
    /// Requires an active task id.
    public func sendEvent(_ event: JsonMap) async {
        guard let taskId else {
            genUiLogger.severe("Cannot send event, no active task ID.")
            return
        }

        let clientEvent: JsonMap = [
            "actionName": event["action"] ?? "",
            "sourceComponentId": event["sourceComponentId"] ?? "",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "resolvedContext": event["context"] ?? ""
        ]

        genUiLogger.finest("Sending client event: \(clientEvent)")

        let dataPart = A2ADataPart(data: ["a2uiEvent": clientEvent])
        var message = A2AMessage()
        message.role = "user"
        message.parts = [dataPart]
        message.contextId = contextIdValue
        message.referenceTaskIds = [taskId]

        var payload = A2AMessageSendParams(message: message)
        payload.extensions = ["https://a2ui.org/a2a-extension/a2ui/v0.8"]

        do {
            try await client.sendMessage(payload)
            genUiLogger.fine("Successfully sent event for task \(taskId) (context \(String(describing: contextIdValue)))")
        } catch {
            genUiLogger.severe("Error sending event: \(error)")
            errorController.send(error)
        }
    }

    /// Releases resources and closes streams.
    /// Call when the connector is no longer needed.
    public func dispose() {
        controller.send(completion: .finished)
        errorController.send(completion: .finished)
    }

    private func processA2uiMessages(_ data: JsonMap) {
        if let pretty = prettyJson(data) {
            genUiLogger.finer("Processing a2ui messages from data part:\n\(pretty)")
        }
        if data.keys.contains("surfaceUpdate") ||
            data.keys.contains("dataModelUpdate") ||
            data.keys.contains("beginRendering") ||
            data.keys.contains("deleteSurface") {
            do {
                let message = try A2uiMessageFactory.fromJson(data)
                controller.send(message)
            } catch {
                errorController.send(error)
            }
        } else {
            genUiLogger.warning("A2A data part did not contain any known A2UI messages.")
        }
    }

    private func prettyJson(_ json: JsonMap) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }
}
