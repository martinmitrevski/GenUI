//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Marker protocol for all A2UI message types.
/// Conforming types represent surface, data, or rendering commands.
public protocol A2uiMessage {}

/// Factory helpers for parsing and describing A2UI messages.
/// Use these helpers when decoding or generating message schemas.
public enum A2uiMessageFactory {
    /// Parses a top-level A2UI message payload.
    /// Returns the matching message type or throws on unknown payloads.
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

    /// Builds a JSON schema for A2UI messages.
    /// Includes the current catalog's surface update schema.
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

/// Message that updates or adds UI components to a surface.
/// Carries the surface id plus the component payloads.
public struct SurfaceUpdate: A2uiMessage {
    public let surfaceId: String
    public let components: [Component]

    /// Creates a surface update for a set of components.
    /// Provide the surface id and component list to apply.
    public init(surfaceId: String, components: [Component]) {
        self.surfaceId = surfaceId
        self.components = components
    }

    /// Parses a surface update from a JSON map.
    /// Uses the `components` array to build `Component` values.
    public static func fromJson(_ json: JsonMap) -> SurfaceUpdate {
        let surfaceId = json[surfaceIdKey] as? String ?? ""
        let components: [Component] = (json["components"] as? [Any] ?? []).compactMap { item -> Component? in
            guard let map = item as? JsonMap else { return nil }
            return Component.fromJson(map)
        }
        return SurfaceUpdate(surfaceId: surfaceId, components: components)
    }

    /// Serializes the update to a JSON map.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        [
            surfaceIdKey: surfaceId,
            "components": components.map { $0.toJson() }
        ]
    }
}

/// Message that mutates the surface data model.
/// Targets a surface id and optional path in the data tree.
public struct DataModelUpdate: A2uiMessage {
    public let surfaceId: String
    public let path: String?
    public let contents: Any

    /// Creates a data model update payload.
    /// Provide the surface id, optional path, and contents.
    public init(surfaceId: String, path: String? = nil, contents: Any) {
        self.surfaceId = surfaceId
        self.path = path
        self.contents = contents
    }

    /// Parses a data model update from a JSON map.
    /// Reads `surfaceId`, `path`, and `contents` fields.
    public static func fromJson(_ json: JsonMap) -> DataModelUpdate {
        DataModelUpdate(
            surfaceId: json[surfaceIdKey] as? String ?? "",
            path: json["path"] as? String,
            contents: json["contents"] as Any
        )
    }
}

/// Message that begins rendering a surface.
/// Defines the root component id and optional styles/catalog id.
public struct BeginRendering: A2uiMessage {
    public let surfaceId: String
    public let root: String
    public let styles: JsonMap?
    public let catalogId: String?

    /// Creates a begin-rendering message.
    /// Provide the root component id and optional styles/catalog id.
    public init(surfaceId: String, root: String, styles: JsonMap? = nil, catalogId: String? = nil) {
        self.surfaceId = surfaceId
        self.root = root
        self.styles = styles
        self.catalogId = catalogId
    }

    /// Parses a begin-rendering message from a JSON map.
    /// Reads surface, root, styles, and catalog fields.
    public static func fromJson(_ json: JsonMap) -> BeginRendering {
        BeginRendering(
            surfaceId: json[surfaceIdKey] as? String ?? "",
            root: json["root"] as? String ?? "",
            styles: json["styles"] as? JsonMap,
            catalogId: json["catalogId"] as? String
        )
    }
}

/// Message that deletes an existing surface.
/// Identified by the surface id to remove.
public struct SurfaceDeletion: A2uiMessage {
    public let surfaceId: String

    /// Creates a surface deletion message.
    /// Provide the surface id to remove.
    public init(surfaceId: String) {
        self.surfaceId = surfaceId
    }

    /// Parses a surface deletion from a JSON map.
    /// Reads the surface id from the payload.
    public static func fromJson(_ json: JsonMap) -> SurfaceDeletion {
        SurfaceDeletion(surfaceId: json[surfaceIdKey] as? String ?? "")
    }
}

/// Errors raised while decoding A2UI payloads.
/// Used by `A2uiMessageFactory` when no message type matches.
public enum GenUiError: Error {
    case unknownMessageType(JsonMap)
}
