//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Marker protocol for A2UI messages.
/// Implemented by surface, data model, and rendering commands.
public protocol A2uiMessage {}

/// A2ui message factory API.
/// Provides the public API for this declaration.
public enum A2uiMessageFactory {
    public static func fromJson(_ json: JsonMap) throws -> A2uiMessage {
        if let surfaceUpdate = json["surfaceUpdate"] as? JsonMap {
            return SurfaceUpdate.fromJson(surfaceUpdate)
        }
        if let dataModelUpdate = json["dataModelUpdate"] as? JsonMap {
            return DataModelUpdate.fromJson(dataModelUpdate)
        }
        if let beginRendering = json["beginRendering"] as? JsonMap {
            return BeginRendering.fromJson(beginRendering)
        }
        if let deleteSurface = json["deleteSurface"] as? JsonMap {
            return SurfaceDeletion.fromJson(deleteSurface)
        }
        throw GenUiError.unknownMessageType(json)
    }

    public static func a2uiMessageSchema(catalog: Catalog) -> Schema {
        S.object(
            title: "A2UI Message Schema",
            description: "Describes a JSON payload for an A2UI (Agent to UI) message, which is used to dynamically construct and update user interfaces. A message MUST contain exactly ONE of the action properties: 'beginRendering', 'surfaceUpdate', 'dataModelUpdate', or 'deleteSurface'.",
            properties: [
                "surfaceUpdate": A2uiSchemas.surfaceUpdateSchema(catalog: catalog),
                "dataModelUpdate": A2uiSchemas.dataModelUpdateSchema(),
                "beginRendering": A2uiSchemas.beginRenderingSchema(),
                "deleteSurface": A2uiSchemas.surfaceDeletionSchema()
            ]
        )
    }
}

/// Message that updates or adds UI components.
/// Carries a surface id and a list of Component definitions.
public struct SurfaceUpdate: A2uiMessage {
    public let surfaceId: String
    public let components: [Component]

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(surfaceId: String, components: [Component]) {
        self.surfaceId = surfaceId
        self.components = components
    }

    public static func fromJson(_ json: JsonMap) -> SurfaceUpdate {
        let surfaceId = json[surfaceIdKey] as? String ?? ""
        let components: [Component] = (json["components"] as? [Any] ?? []).compactMap { item -> Component? in
            guard let map = item as? JsonMap else { return nil }
            return Component.fromJson(map)
        }
        return SurfaceUpdate(surfaceId: surfaceId, components: components)
    }

    /// Serializes the value to a JSON-compatible dictionary.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        [
            surfaceIdKey: surfaceId,
            "components": components.map { $0.toJson() }
        ]
    }
}

/// Message that mutates the data model.
/// Targets a surface id and optional data path.
public struct DataModelUpdate: A2uiMessage {
    public let surfaceId: String
    public let path: String?
    public let contents: Any

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(surfaceId: String, path: String? = nil, contents: Any) {
        self.surfaceId = surfaceId
        self.path = path
        self.contents = contents
    }

    public static func fromJson(_ json: JsonMap) -> DataModelUpdate {
        DataModelUpdate(
            surfaceId: json[surfaceIdKey] as? String ?? "",
            path: json["path"] as? String,
            contents: json["contents"] as Any
        )
    }
}

/// Message that starts rendering a surface.
/// Defines the root component id and optional catalog/styles.
public struct BeginRendering: A2uiMessage {
    public let surfaceId: String
    public let root: String
    public let styles: JsonMap?
    public let catalogId: String?

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(surfaceId: String, root: String, styles: JsonMap? = nil, catalogId: String? = nil) {
        self.surfaceId = surfaceId
        self.root = root
        self.styles = styles
        self.catalogId = catalogId
    }

    public static func fromJson(_ json: JsonMap) -> BeginRendering {
        BeginRendering(
            surfaceId: json[surfaceIdKey] as? String ?? "",
            root: json["root"] as? String ?? "",
            styles: json["styles"] as? JsonMap,
            catalogId: json["catalogId"] as? String
        )
    }
}

/// Message that removes a surface.
/// Identified by the surface id to delete.
public struct SurfaceDeletion: A2uiMessage {
    public let surfaceId: String

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(surfaceId: String) {
        self.surfaceId = surfaceId
    }

    public static func fromJson(_ json: JsonMap) -> SurfaceDeletion {
        SurfaceDeletion(surfaceId: json[surfaceIdKey] as? String ?? "")
    }
}

/// Gen ui error API.
/// Provides the public API for this declaration.
public enum GenUiError: Error {
    case unknownMessageType(JsonMap)
}
