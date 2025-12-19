//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Protocol for tool-call parts used by integrations.
/// Supports parsing from JSON and serialization.
public protocol Part {
    /// Parses a part from a JSON map.
    /// Throws when the payload cannot be decoded.
    static func fromJson(_ json: JsonMap) throws -> Part

    /// Serializes the part to a JSON map.
    /// Use this when emitting tool payloads.
    func toJson() -> JsonMap
}

/// Represents a tool invocation request.
/// Contains the tool name and raw arguments.
public struct ToolCall: Part {
    public let args: Any?
    public let name: String

    /// Creates a tool call with name and raw arguments.
    /// Use this when constructing tool calls manually.
    public init(args: Any?, name: String) {
        self.args = args
        self.name = name
    }

    /// Parses a tool call from a JSON map.
    /// Expects `"type": "ToolCall"` in the payload.
    public static func fromJson(_ json: JsonMap) throws -> Part {
        guard let type = json["type"] as? String, type == "ToolCall" else {
            throw GenUiError.unknownMessageType(json)
        }
        return ToolCall(args: json["args"], name: json["name"] as? String ?? "")
    }

    /// Serializes the tool call to a JSON map.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        [
            "type": "ToolCall",
            "args": args as Any,
            "name": name
        ]
    }
}

/// Function declaration sent to an LLM.
/// Contains tool name, description, and parameter schema.
public struct GenUiFunctionDeclaration {
    public let description: String
    public let name: String
    public let parameters: Any?

    /// Creates a function declaration for an LLM.
    /// Provide the name, description, and optional schema.
    public init(description: String, name: String, parameters: Any? = nil) {
        self.description = description
        self.name = name
        self.parameters = parameters
    }

    /// Parses a function declaration from a JSON map.
    /// Reads name, description, and parameters fields.
    public static func fromJson(_ json: JsonMap) -> GenUiFunctionDeclaration {
        GenUiFunctionDeclaration(
            description: json["description"] as? String ?? "",
            name: json["name"] as? String ?? "",
            parameters: json["parameters"]
        )
    }

    /// Serializes the declaration to a JSON map.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        [
            "description": description,
            "name": name,
            "parameters": parameters as Any
        ]
    }
}

/// Parsed result of a tool call.
/// Includes generated messages and target surface id.
public struct ParsedToolCall {
    public let messages: [A2uiMessage]
    public let surfaceId: String

    /// Creates a parsed tool call result.
    /// Provide the generated messages and surface id.
    public init(messages: [A2uiMessage], surfaceId: String) {
        self.messages = messages
        self.surfaceId = surfaceId
    }
}
