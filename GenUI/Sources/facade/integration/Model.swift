//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Protocol for tool call parts.
/// Supports parsing from JSON and serialization.
public protocol Part {
    static func fromJson(_ json: JsonMap) throws -> Part
    func toJson() -> JsonMap
}

/// Represents a tool invocation request.
/// Contains the tool name and raw arguments.
public struct ToolCall: Part {
    public let args: Any?
    public let name: String

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(args: Any?, name: String) {
        self.args = args
        self.name = name
    }

    public static func fromJson(_ json: JsonMap) throws -> Part {
        guard let type = json["type"] as? String, type == "ToolCall" else {
            throw GenUiError.unknownMessageType(json)
        }
        return ToolCall(args: json["args"], name: json["name"] as? String ?? "")
    }

    /// Serializes the value to a JSON-compatible dictionary.
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

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(description: String, name: String, parameters: Any? = nil) {
        self.description = description
        self.name = name
        self.parameters = parameters
    }

    public static func fromJson(_ json: JsonMap) -> GenUiFunctionDeclaration {
        GenUiFunctionDeclaration(
            description: json["description"] as? String ?? "",
            name: json["name"] as? String ?? "",
            parameters: json["parameters"]
        )
    }

    /// Serializes the value to a JSON-compatible dictionary.
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

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(messages: [A2uiMessage], surfaceId: String) {
        self.messages = messages
        self.surfaceId = surfaceId
    }
}
