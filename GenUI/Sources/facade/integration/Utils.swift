//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Builds the system prompt for UI tool usage.
/// Injects tool names and surface id guidance.
public func genUiTechPrompt(_ toolNames: [String]) -> String {
    let toolDescription: String
    if toolNames.count > 1 {
        let toolDesc = toolNames.map { "\"\($0)\"" }.joined(separator: ",")
        toolDescription = "the following UI generation tools: \(toolDesc)"
    } else {
        toolDescription = "the UI generation tool \"\(toolNames.first ?? "")\""
    }

    return """
To show generated UI, use \(toolDescription).
When generating UI, always provide a unique \(surfaceIdKey) to identify the UI surface:

* To create new UI, use a new \(surfaceIdKey).
* To update existing UI, use the existing \(surfaceIdKey).

Use the root component id: 'root'.
Ensure one of the generated components has an id of 'root'.
"""
}

/// Builds a tool declaration for a catalog.
/// Uses the surfaceUpdate schema as parameters.
public func catalogToFunctionDeclaration(
    _ catalog: Catalog,
    toolName: String,
    toolDescription: String
) -> GenUiFunctionDeclaration {
    GenUiFunctionDeclaration(
        description: toolDescription,
        name: toolName,
        parameters: A2uiSchemas.surfaceUpdateSchema(catalog: catalog)
    )
}

/// Converts a tool call into A2UI messages.
/// Returns the messages and target surface id.
public func parseToolCall(_ toolCall: ToolCall, toolName: String) -> ParsedToolCall {
    precondition(toolCall.name == toolName)

    let messageJson: JsonMap = ["surfaceUpdate": toolCall.args as Any]
    let surfaceUpdateMessage = try? A2uiMessageFactory.fromJson(messageJson)

    let surfaceId = (toolCall.args as? JsonMap)?[surfaceIdKey] as? String ?? ""
    let beginRenderingMessage = BeginRendering(surfaceId: surfaceId, root: "root")

    let messages = [surfaceUpdateMessage, beginRenderingMessage].compactMap { $0 }
    return ParsedToolCall(messages: messages, surfaceId: surfaceId)
}

/// Wraps catalog example JSON into a ToolCall.
/// Used for testing or prompt examples.
public func catalogExampleToToolCall(
    _ example: JsonMap,
    toolName: String,
    surfaceId: String
) -> ToolCall {
    let messageJson: JsonMap = ["surfaceUpdate": example]
    _ = try? A2uiMessageFactory.fromJson(messageJson)

    return ToolCall(
        args: [surfaceIdKey: surfaceId, "surfaceUpdate": messageJson],
        name: toolName
    )
}
