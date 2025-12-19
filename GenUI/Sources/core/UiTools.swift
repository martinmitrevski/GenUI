//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

public final class SurfaceUpdateTool: AiTool<JsonMap> {
    private let handleMessage: (A2uiMessage) -> Void

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(handleMessage: @escaping (A2uiMessage) -> Void, catalog: Catalog) {
        self.handleMessage = handleMessage
        super.init(
            name: "surfaceUpdate",
            description: "Updates a surface with a new set of components.",
            parameters: A2uiSchemas.surfaceUpdateSchema(catalog: catalog)
        )
    }

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

public final class DeleteSurfaceTool: AiTool<JsonMap> {
    private let handleMessage: (A2uiMessage) -> Void

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
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

    public override func invoke(_ args: JsonMap) async -> JsonMap {
        let surfaceId = args[surfaceIdKey] as? String ?? ""
        handleMessage(SurfaceDeletion(surfaceId: surfaceId))
        return ["status": "Surface \(surfaceId) deleted."]
    }
}

public final class BeginRenderingTool: AiTool<JsonMap> {
    private let handleMessage: (A2uiMessage) -> Void
    private let catalogId: String?

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(handleMessage: @escaping (A2uiMessage) -> Void, catalogId: String? = nil) {
        self.handleMessage = handleMessage
        self.catalogId = catalogId
        super.init(
            name: "beginRendering",
            description: "Signals the client to begin rendering a surface with a root component.",
            parameters: A2uiSchemas.beginRenderingSchemaNoCatalogId()
        )
    }

    public override func invoke(_ args: JsonMap) async -> JsonMap {
        let surfaceId = args[surfaceIdKey] as? String ?? ""
        let root = args["root"] as? String ?? ""
        handleMessage(BeginRendering(surfaceId: surfaceId, root: root, catalogId: catalogId))
        return ["status": "Surface \(surfaceId) rendered and waiting for user input."]
    }
}
