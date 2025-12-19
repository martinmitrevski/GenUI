//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Marker protocol for chat message parts.
/// Implementations support text, data, images, and tool payloads.
public protocol MessagePart {}

/// Text payload for a chat message.
/// Stores the raw string content for model input.
public struct TextPart: MessagePart {
    public let text: String

    /// Creates a text part with the provided content.
    /// Use this for plain text messages.
    public init(_ text: String) {
        self.text = text
    }
}

/// Structured data payload for a chat message.
/// Carries a JSON-like map of values.
public struct DataPart: MessagePart {
    public let data: [String: Any]?

    /// Creates a data part with optional JSON data.
    /// Use this for structured tool or model inputs.
    public init(_ data: [String: Any]?) {
        self.data = data
    }
}

/// Image payload for a chat message.
/// Supports inline bytes, base64, or remote URLs.
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

    /// Creates an image part from raw bytes.
    /// Provide the MIME type for correct decoding.
    public static func fromBytes(_ bytes: Data, mimeType: String) -> ImagePart {
        ImagePart(bytes: bytes, mimeType: mimeType)
    }

    /// Creates an image part from a base64 string.
    /// Provide the MIME type for correct decoding.
    public static func fromBase64(_ base64: String, mimeType: String) -> ImagePart {
        ImagePart(base64: base64, mimeType: mimeType)
    }

    /// Creates an image part from a remote URL.
    /// Provide the MIME type for correct decoding.
    public static func fromUrl(_ url: URL, mimeType: String) -> ImagePart {
        ImagePart(url: url, mimeType: mimeType)
    }
}

/// Tool invocation request issued by the model.
/// Includes tool name, arguments, and a call id.
public struct ToolCallPart: MessagePart {
    public let toolName: String
    public let arguments: [String: Any?]
    public let id: String

    /// Creates a tool call part with explicit arguments.
    /// Use this when constructing tool calls manually.
    public init(id: String, toolName: String, arguments: [String: Any?]) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
    }
}

/// Tool call result payload.
/// Pairs a call id with the tool output string.
public struct ToolResultPart: MessagePart {
    public let callId: String
    public let result: String

    /// Creates a tool result payload.
    /// Use this when returning tool output to the model.
    public init(callId: String, result: String) {
        self.callId = callId
        self.result = result
    }
}

/// Model reasoning block or "thinking" segment.
/// Used for provider-specific internal thoughts.
public struct ThinkingPart: MessagePart {
    public let text: String

    /// Creates a reasoning part with the given text.
    /// Use this for provider-specific thought segments.
    public init(_ text: String) {
        self.text = text
    }
}

/// Marker protocol for chat history messages.
/// Implemented by user, AI, and tool result message types.
public protocol ChatMessage {}

/// Internal message for the chat log.
/// Use for system notes that are not user-visible.
public struct InternalMessage: ChatMessage {
    public let text: String

    /// Creates an internal message with text content.
    /// Use this for system-level entries.
    public init(_ text: String) {
        self.text = text
    }
}

/// User-authored message composed of message parts.
/// Provides a flattened text representation for convenience.
public struct UserMessage: ChatMessage {
    public let parts: [MessagePart]
    public let text: String

    /// Creates a user message from message parts.
    /// Flattens text parts into a combined string.
    public init(_ parts: [MessagePart]) {
        self.parts = parts
        self.text = parts.compactMap { ($0 as? TextPart)?.text }.joined(separator: "\n")
    }

    /// Builds a user message from a single text string.
    /// Useful for quick construction of user input.
    public static func text(_ text: String) -> UserMessage {
        UserMessage([TextPart(text)])
    }
}

/// Message representing UI interactions.
/// Used to forward UI events back to the agent.
public struct UserUiInteractionMessage: ChatMessage {
    public let parts: [MessagePart]
    public let text: String

    /// Creates a UI interaction message from message parts.
    /// Flattens text parts into a combined string.
    public init(_ parts: [MessagePart]) {
        self.parts = parts
        self.text = parts.compactMap { ($0 as? TextPart)?.text }.joined(separator: "\n")
    }

    /// Builds a UI interaction message from a text string.
    /// Use for quick composition of event text.
    public static func text(_ text: String) -> UserUiInteractionMessage {
        UserUiInteractionMessage([TextPart(text)])
    }
}

/// AI-authored message composed of message parts.
/// Stores parts and a flattened text representation.
public struct AiTextMessage: ChatMessage {
    public let parts: [MessagePart]
    public let text: String

    /// Creates an AI text message from message parts.
    /// Flattens text parts into a combined string.
    public init(_ parts: [MessagePart]) {
        self.parts = parts
        self.text = parts.compactMap { ($0 as? TextPart)?.text }.joined(separator: "\n")
    }

    /// Builds an AI text message from a single string.
    /// Use this for simple model responses.
    public static func text(_ text: String) -> AiTextMessage {
        AiTextMessage([TextPart(text)])
    }
}

/// Message carrying tool results for the model.
/// Bundles one or more tool result parts.
public struct ToolResponseMessage: ChatMessage {
    public let results: [ToolResultPart]

    /// Creates a tool response message.
    /// Use this to return tool outputs to the model.
    public init(_ results: [ToolResultPart]) {
        self.results = results
    }
}

/// AI-authored UI message.
/// Contains a `UiDefinition` and surface id metadata.
public struct AiUiMessage: ChatMessage {
    public let definition: UiDefinition
    public let uiKey: String
    public let surfaceId: String
    public let parts: [MessagePart]

    /// Creates an AI UI message from a UI definition.
    /// Generates a UI key and surface id if none is provided.
    public init(definition: UiDefinition, surfaceId: String? = nil) {
        self.definition = definition
        self.uiKey = UUID().uuidString
        self.surfaceId = surfaceId ?? UUID().uuidString
        self.parts = [TextPart(definition.asContextDescriptionText())]
    }
}
