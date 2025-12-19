//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Tool that applies surface updates from tool calls.
/// Converts JSON payloads into `SurfaceUpdate` messages.
public final class SurfaceUpdateTool: AiTool<JsonMap> {
    private let handleMessage: (A2uiMessage) -> Void

    /// Creates a surface update tool.
    /// Provide a handler to receive parsed A2UI messages.
    public init(handleMessage: @escaping (A2uiMessage) -> Void, catalog: Catalog) {
        self.handleMessage = handleMessage
        super.init(
            name: "surfaceUpdate",
            description: "Updates a surface with a new set of components.",
            parameters: A2uiSchemas.surfaceUpdateSchema(catalog: catalog)
        )
    }

    /// Parses args into a `SurfaceUpdate` and forwards it.
    /// Returns a status payload for the tool response.
    public override func invoke(_ args: JsonMap) async -> JsonMap {
        let surfaceId = args[surfaceIdKey] as? String ?? ""
        let components = (args["components"] as? [Any] ?? []).compactMap { item -> Component? in
            guard let component = item as? JsonMap else { return nil }
            return Component(
                id: component["id"] as? String ?? "",
                componentProperties: component["component"] as? JsonMap ?? [:],
                weight: (component["weight"] as? NSNumber)?.intValue
            )
        }
        handleMessage(SurfaceUpdate(surfaceId: surfaceId, components: components))
        return [
            surfaceIdKey: surfaceId,
            "status": "UI Surface \(surfaceId) updated."
        ]
    }
}

/// Tool that deletes an existing surface.
/// Converts tool calls into `SurfaceDeletion` messages.
public final class DeleteSurfaceTool: AiTool<JsonMap> {
    private let handleMessage: (A2uiMessage) -> Void

    /// Creates a delete-surface tool.
    /// Provide a handler to receive parsed A2UI messages.
    public init(handleMessage: @escaping (A2uiMessage) -> Void) {
        self.handleMessage = handleMessage
        super.init(
            name: "deleteSurface",
            description: "Removes a UI surface that is no longer needed.",
            parameters: S.object(
                properties: [
                    surfaceIdKey: S.string(description: "The unique identifier for the UI surface to remove.")
                ],
                required: [surfaceIdKey]
            )
        )
    }

    /// Parses args into a `SurfaceDeletion` and forwards it.
    /// Returns a status payload for the tool response.
    public override func invoke(_ args: JsonMap) async -> JsonMap {
        let surfaceId = args[surfaceIdKey] as? String ?? ""
        handleMessage(SurfaceDeletion(surfaceId: surfaceId))
        return ["status": "Surface \(surfaceId) deleted."]
    }
}

/// Tool that begins rendering a surface.
/// Converts tool calls into `BeginRendering` messages.
public final class BeginRenderingTool: AiTool<JsonMap> {
    private let handleMessage: (A2uiMessage) -> Void
    private let catalogId: String?

    /// Creates a begin-rendering tool.
    /// Provide a handler and optional catalog id override.
    public init(handleMessage: @escaping (A2uiMessage) -> Void, catalogId: String? = nil) {
        self.handleMessage = handleMessage
        self.catalogId = catalogId
        super.init(
            name: "beginRendering",
            description: "Signals the client to begin rendering a surface with a root component.",
            parameters: A2uiSchemas.beginRenderingSchemaNoCatalogId()
        )
    }

    /// Parses args into a `BeginRendering` and forwards it.
    /// Returns a status payload for the tool response.
    public override func invoke(_ args: JsonMap) async -> JsonMap {
        let surfaceId = args[surfaceIdKey] as? String ?? ""
        let root = args["root"] as? String ?? ""
        handleMessage(BeginRendering(surfaceId: surfaceId, root: root, catalogId: catalogId))
        return ["status": "Surface \(surfaceId) rendered and waiting for user input."]
    }
}
