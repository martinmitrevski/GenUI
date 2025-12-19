//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Protocol for parts of a chat message.
/// Supports multimodal content like text, data, and images.
public protocol MessagePart {}

/// Text payload for a chat message.
/// Holds the raw string content.
public struct TextPart: MessagePart {
    public let text: String

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(_ text: String) {
        self.text = text
    }
}

/// Structured data payload for a chat message.
/// Carries a JSON-like map of values.
public struct DataPart: MessagePart {
    public let data: [String: Any]?

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(_ data: [String: Any]?) {
        self.data = data
    }
}

public final class ImagePart: MessagePart {
    public let bytes: Data?
    public let base64: String?
    public let url: URL?
    public let mimeType: String

    private init(bytes: Data? = nil, base64: String? = nil, url: URL? = nil, mimeType: String) {
        self.bytes = bytes
        self.base64 = base64
        self.url = url
        self.mimeType = mimeType
    }

    public static func fromBytes(_ bytes: Data, mimeType: String) -> ImagePart {
        ImagePart(bytes: bytes, mimeType: mimeType)
    }

    public static func fromBase64(_ base64: String, mimeType: String) -> ImagePart {
        ImagePart(base64: base64, mimeType: mimeType)
    }

    public static func fromUrl(_ url: URL, mimeType: String) -> ImagePart {
        ImagePart(url: url, mimeType: mimeType)
    }
}

/// Represents a tool invocation request.
/// Includes tool name, arguments, and a call id.
public struct ToolCallPart: MessagePart {
    public let toolName: String
    public let arguments: [String: Any?]
    public let id: String

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(id: String, toolName: String, arguments: [String: Any?]) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
    }
}

/// Represents a tool call result.
/// Pairs a call id with the tool output string.
public struct ToolResultPart: MessagePart {
    public let callId: String
    public let result: String

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(callId: String, result: String) {
        self.callId = callId
        self.result = result
    }
}

/// Represents a model reasoning block.
/// Used for provider-specific thinking text.
public struct ThinkingPart: MessagePart {
    public let text: String

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(_ text: String) {
        self.text = text
    }
}

/// Protocol for chat history messages.
/// Implemented by user, AI, and tool result message types.
public protocol ChatMessage {}

/// System/internal message for the chat log.
/// Used for non-user-visible entries.
public struct InternalMessage: ChatMessage {
    public let text: String

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(_ text: String) {
        self.text = text
    }
}

/// User-authored message with optional multimodal parts.
/// Provides a flattened text representation.
public struct UserMessage: ChatMessage {
    public let parts: [MessagePart]
    public let text: String

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(_ parts: [MessagePart]) {
        self.parts = parts
        self.text = parts.compactMap { ($0 as? TextPart)?.text }.joined(separator: "\n")
    }

    public static func text(_ text: String) -> UserMessage {
        UserMessage([TextPart(text)])
    }
}

/// Message representing UI interactions.
/// Used to forward UI events back to the agent.
public struct UserUiInteractionMessage: ChatMessage {
    public let parts: [MessagePart]
    public let text: String

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(_ parts: [MessagePart]) {
        self.parts = parts
        self.text = parts.compactMap { ($0 as? TextPart)?.text }.joined(separator: "\n")
    }

    public static func text(_ text: String) -> UserUiInteractionMessage {
        UserUiInteractionMessage([TextPart(text)])
    }
}

/// AI-authored text message.
/// Stores parts and a flattened text representation.
public struct AiTextMessage: ChatMessage {
    public let parts: [MessagePart]
    public let text: String

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(_ parts: [MessagePart]) {
        self.parts = parts
        self.text = parts.compactMap { ($0 as? TextPart)?.text }.joined(separator: "\n")
    }

    public static func text(_ text: String) -> AiTextMessage {
        AiTextMessage([TextPart(text)])
    }
}

/// Message carrying tool results.
/// Bundles ToolResultPart values for the model.
public struct ToolResponseMessage: ChatMessage {
    public let results: [ToolResultPart]

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(_ results: [ToolResultPart]) {
        self.results = results
    }
}

/// AI-authored UI message.
/// Contains a UiDefinition and surface id metadata.
public struct AiUiMessage: ChatMessage {
    public let definition: UiDefinition
    public let uiKey: String
    public let surfaceId: String
    public let parts: [MessagePart]

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(definition: UiDefinition, surfaceId: String? = nil) {
        self.definition = definition
        self.uiKey = UUID().uuidString
        self.surfaceId = surfaceId ?? UUID().uuidString
        self.parts = [TextPart(definition.asContextDescriptionText())]
    }
}
