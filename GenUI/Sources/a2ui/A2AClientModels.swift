//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Protocol for A2A transport clients.
/// Defines methods for cards, streaming, and send requests.
public protocol A2AClientProtocol {
    func getAgentCard() async throws -> A2AAgentCard
    func sendMessageStream(_ payload: A2AMessageSendParams) -> AsyncThrowingStream<A2ASendStreamMessageResponse, Error>
    func sendMessage(_ payload: A2AMessageSendParams) async throws
}

/// Card describing an A2A agent.
/// Includes name, description, and version fields.
public struct A2AAgentCard {
    public let name: String
    public let description: String
    public let version: String

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(name: String, description: String, version: String) {
        self.name = name
        self.description = description
        self.version = version
    }
}

/// Protocol for A2A message parts.
/// Supports JSON serialization for transport.
public protocol A2APart {
    func toJson() -> JsonMap
}

/// Text part for an A2A message.
/// Encodes a string payload.
public struct A2ATextPart: A2APart {
    public var text: String

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(text: String = "") {
        self.text = text
    }

    /// Serializes the value to a JSON-compatible dictionary.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        ["type": "text", "text": text]
    }
}

/// Data part for an A2A message.
/// Encodes a JSON-like payload.
public struct A2ADataPart: A2APart {
    public var data: JsonMap

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(data: JsonMap = [:]) {
        self.data = data
    }

    /// Serializes the value to a JSON-compatible dictionary.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        ["type": "data", "data": data]
    }
}

/// File part for an A2A message.
/// Wraps a file reference or payload.
public struct A2AFilePart: A2APart {
    public var file: A2AFile

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(file: A2AFile) {
        self.file = file
    }

    /// Serializes the value to a JSON-compatible dictionary.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        ["type": "file", "file": file.toJson()]
    }
}

/// Protocol for A2A file payloads.
/// Supports JSON serialization variants.
public protocol A2AFile {
    func toJson() -> JsonMap
}

/// A2A file descriptor that references a URI.
/// Includes the mime type and location.
public struct A2AFileWithUri: A2AFile {
    public var uri: String
    public var mimeType: String

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(uri: String, mimeType: String) {
        self.uri = uri
        self.mimeType = mimeType
    }

    /// Serializes the value to a JSON-compatible dictionary.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        ["uri": uri, "mimeType": mimeType]
    }
}

/// A2A file payload encoded as base64 bytes.
/// Includes the mime type for decoding.
public struct A2AFileWithBytes: A2AFile {
    public var bytes: String
    public var mimeType: String

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(bytes: String, mimeType: String) {
        self.bytes = bytes
        self.mimeType = mimeType
    }

    /// Serializes the value to a JSON-compatible dictionary.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        ["bytes": bytes, "mimeType": mimeType]
    }
}

/// A2A message container.
/// Carries role, parts, and optional task references.
public struct A2AMessage: A2AResult {
    public var messageId: String
    public var role: String
    public var parts: [A2APart]
    public var referenceTaskIds: [String]?
    public var contextId: String?
    public var metadata: JsonMap?

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(
        messageId: String = UUID().uuidString,
        role: String = "user",
        parts: [A2APart] = [],
        referenceTaskIds: [String]? = nil,
        contextId: String? = nil,
        metadata: JsonMap? = nil
    ) {
        self.messageId = messageId
        self.role = role
        self.parts = parts
        self.referenceTaskIds = referenceTaskIds
        self.contextId = contextId
        self.metadata = metadata
    }

    /// Serializes the value to a JSON-compatible dictionary.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        var json: JsonMap = [
            "messageId": messageId,
            "role": role,
            "parts": parts.map { $0.toJson() }
        ]
        if let referenceTaskIds {
            json["referenceTaskIds"] = referenceTaskIds
        }
        if let contextId {
            json["contextId"] = contextId
        }
        if let metadata {
            json["metadata"] = metadata
        }
        return json
    }
}

/// Request payload for sending an A2A message.
/// Wraps the message and optional extensions.
public struct A2AMessageSendParams {
    public var message: A2AMessage
    public var extensions: [String]

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(message: A2AMessage, extensions: [String] = []) {
        self.message = message
        self.extensions = extensions
    }

    /// Serializes the value to a JSON-compatible dictionary.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        var json: JsonMap = ["message": message.toJson()]
        if !extensions.isEmpty {
            json["extensions"] = extensions
        }
        return json
    }
}

/// Protocol for A2A stream responses.
/// Differentiates between success and error events.
public protocol A2ASendStreamMessageResponse {
    var isError: Bool { get }
    func toJson() -> JsonMap
}

/// Error response wrapper for A2A streams.
/// Carries JSON-RPC error metadata.
public struct A2AJSONRPCErrorResponseSSM: A2ASendStreamMessageResponse {
    public var error: A2AError?

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(error: A2AError? = nil) {
        self.error = error
    }

    public var isError: Bool { true }

    /// Serializes the value to a JSON-compatible dictionary.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        ["error": error?.toJson() as Any]
    }
}

/// Success response wrapper for A2A streams.
/// Carries the result payload.
public struct A2ASendStreamMessageSuccessResponse: A2ASendStreamMessageResponse {
    public var result: A2AResult?

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(result: A2AResult? = nil) {
        self.result = result
    }

    public var isError: Bool { false }

    /// Serializes the value to a JSON-compatible dictionary.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        ["result": result?.toJson() as Any]
    }
}

/// A2A error metadata container.
/// Holds the RPC error code.
public struct A2AError {
    public var rpcErrorCode: Int?

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(rpcErrorCode: Int? = nil) {
        self.rpcErrorCode = rpcErrorCode
    }

    /// Serializes the value to a JSON-compatible dictionary.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        ["rpcErrorCode": rpcErrorCode as Any]
    }
}

/// Protocol for A2A result payloads.
/// Implemented by messages, tasks, and status updates.
public protocol A2AResult {
    func toJson() -> JsonMap
}

/// A2A task container.
/// Includes task id, context id, and status.
public struct A2ATask: A2AResult {
    public var id: String
    public var contextId: String?
    public var status: A2ATaskStatus?

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(id: String, contextId: String? = nil, status: A2ATaskStatus? = nil) {
        self.id = id
        self.contextId = contextId
        self.status = status
    }

    /// Serializes the value to a JSON-compatible dictionary.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        var json: JsonMap = ["id": id]
        if let contextId {
            json["contextId"] = contextId
        }
        if let status {
            json["status"] = status.toJson()
        }
        return json
    }
}

/// Task status payload for A2A.
/// Optionally carries the latest message.
public struct A2ATaskStatus {
    public var message: A2AMessage?

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(message: A2AMessage? = nil) {
        self.message = message
    }

    /// Serializes the value to a JSON-compatible dictionary.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        ["message": message?.toJson() as Any]
    }
}

/// Task status update result for streaming.
/// Wraps the status payload.
public struct A2ATaskStatusUpdateEvent: A2AResult {
    public var status: A2ATaskStatus?

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(status: A2ATaskStatus? = nil) {
        self.status = status
    }

    /// Serializes the value to a JSON-compatible dictionary.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        ["status": status?.toJson() as Any]
    }
}

/// Errors emitted by A2A client implementations.
/// Used by the default noop client.
public enum A2AClientError: Error {
    case notImplemented
}

public final class NoopA2AClient: A2AClientProtocol {
    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init() {}

    /// Fetches the agent card from the client.
    /// Returns name, description, and version metadata.
    public func getAgentCard() async throws -> A2AAgentCard {
        throw A2AClientError.notImplemented
    }

    /// Sends a request or event.
    /// Performs the underlying transport operation asynchronously.
    public func sendMessageStream(_ payload: A2AMessageSendParams) -> AsyncThrowingStream<A2ASendStreamMessageResponse, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: A2AClientError.notImplemented)
        }
    }

    /// Sends a request or event.
    /// Performs the underlying transport operation asynchronously.
    public func sendMessage(_ payload: A2AMessageSendParams) async throws {
        throw A2AClientError.notImplemented
    }
}
