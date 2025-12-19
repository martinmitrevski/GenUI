//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Schema builders for A2UI payloads and references.
/// Use these helpers to construct JSON schemas for tool definitions.
public enum A2uiSchemas {
    /// Builds a schema for string references.
    /// Supports data model paths or literal string values.
    public static func stringReference(description: String? = nil, enumValues: [String]? = nil) -> Schema {
        S.object(
            description: description,
            properties: [
                "path": S.string(
                    description: "A relative or absolute path in the data model.",
                    enumValues: enumValues
                ),
                "literalString": S.string(enumValues: enumValues)
            ]
        )
    }

    /// Builds a schema for numeric references.
    /// Supports data model paths or literal numbers.
    public static func numberReference(description: String? = nil) -> Schema {
        S.object(
            description: description,
            properties: [
                "path": S.string(description: "A relative or absolute path in the data model."),
                "literalNumber": S.number()
            ]
        )
    }

    /// Builds a schema for boolean references.
    /// Supports data model paths or literal booleans.
    public static func booleanReference(description: String? = nil) -> Schema {
        S.object(
            description: description,
            properties: [
                "path": S.string(description: "A relative or absolute path in the data model."),
                "literalBoolean": S.boolean()
            ]
        )
    }

    /// Builds a schema for a single component id reference.
    /// Use this for properties that point to one child component.
    public static func componentReference(description: String? = nil) -> Schema {
        S.string(description: description)
    }

    /// Builds a schema for child component lists.
    /// Supports explicit lists or template bindings.
    public static func componentArrayReference(description: String? = nil) -> Schema {
        S.object(
            description: description,
            properties: [
                "explicitList": S.list(items: componentReference()),
                "template": S.object(
                    properties: [
                        "componentId": S.string(),
                        "dataBinding": S.string()
                    ],
                    required: ["componentId", "dataBinding"]
                )
            ]
        )
    }

    /// Builds a schema for UI actions.
    /// Includes an action name and optional key/value context payloads.
    public static func action(description: String? = nil) -> Schema {
        S.object(
            description: description,
            properties: [
                "name": S.string(),
                "context": S.list(
                    description: "A list of name-value pairs to be sent with the action to include data associated with the action, e.g. values that are submitted.",
                    items: S.object(
                        properties: [
                            "key": S.string(),
                            "value": S.object(
                                properties: [
                                    "path": S.string(description: "A path in the data model which should be bound to an input element, e.g. a string reference for a text field, or number reference for a slider."),
                                    "literalString": S.string(description: "A literal string relevant to the action"),
                                    "literalNumber": S.number(description: "A literal number relevant to the action"),
                                    "literalBoolean": S.boolean(description: "A literal boolean relevant to the action")
                                ]
                            )
                        ],
                        required: ["key", "value"]
                    )
                )
            ],
            required: ["name"]
        )
    }

    /// Builds a schema for string array references.
    /// Supports data model paths or literal string lists.
    public static func stringArrayReference(description: String? = nil) -> Schema {
        S.object(
            description: description,
            properties: [
                "path": S.string(description: "A relative or absolute path in the data model."),
                "literalArray": S.list(items: S.string())
            ]
        )
    }

    /// Builds a schema for begin-rendering messages.
    /// Includes surface id, root id, styles, and catalog id.
    public static func beginRenderingSchema() -> Schema {
        S.object(
            properties: [
                surfaceIdKey: S.string(description: "The surface ID of the surface to render."),
                "root": S.string(description: "The root widget ID for the surface. All components must be descendents of this root in order to be displayed."),
                "catalogId": S.string(description: "The identifier of the component catalog to use for this surface."),
                "styles": S.object(
                    properties: [
                        "font": S.string(description: "The base font for this surface"),
                        "primaryColor": S.string(description: "The seed color for the theme of this surface.")
                    ]
                )
            ],
            required: [surfaceIdKey, "root"]
        )
    }

    /// Builds a begin-rendering schema without catalog id.
    /// Use when the catalog is implicitly selected.
    public static func beginRenderingSchemaNoCatalogId() -> Schema {
        S.object(
            properties: [
                surfaceIdKey: S.string(description: "The surface ID of the surface to render."),
                "root": S.string(description: "The root widget ID for the surface. All components must be descendents of this root in order to be displayed."),
                "styles": S.object(
                    properties: [
                        "font": S.string(description: "The base font for this surface"),
                        "primaryColor": S.string(description: "The seed color for the theme of this surface.")
                    ]
                )
            ],
            required: [surfaceIdKey, "root"]
        )
    }

    /// Builds a schema for surface deletion messages.
    /// Includes the surface id to remove.
    public static func surfaceDeletionSchema() -> Schema {
        S.object(
            properties: [surfaceIdKey: S.string()],
            required: [surfaceIdKey]
        )
    }

    /// Builds a schema for data model update messages.
    /// Includes surface id, optional path, and update contents.
    public static func dataModelUpdateSchema() -> Schema {
        S.object(
            properties: [
                surfaceIdKey: S.string(),
                "path": S.string(),
                "contents": S.any(description: "The new contents to write to the data model.")
            ],
            required: [surfaceIdKey, "contents"]
        )
    }

    /// Builds a schema for surface updates using a catalog.
    /// Expands component definitions from the catalog schema.
    public static func surfaceUpdateSchema(catalog: Catalog) -> Schema {
        var componentProperties: [String: Schema] = [:]
        if let catalogDefinition = catalog.definition as? ObjectSchema,
           let componentsSchema = catalogDefinition.properties["components"] as? ObjectSchema {
            componentProperties = componentsSchema.properties
        }

        return S.object(
            properties: [
                surfaceIdKey: S.string(
                    description: "The unique identifier for the UI surface to create or update. If you are adding a new surface this *must* be a new, unique identified that has never been used for any existing surfaces shown."
                ),
                "components": S.list(
                    description: "A list of component definitions.",
                    items: S.object(
                        description: "Represents a *single* component in a UI widget tree. This component could be one of many supported types.",
                        properties: [
                            "id": S.string(),
                            "weight": S.integer(description: "Optional layout weight for use in Row/Column children."),
                            "component": S.object(
                                description: "A wrapper object that MUST contain exactly one key, which is the name of the component type (e.g., 'Text'). The value is an object containing the properties for that specific component.",
                                properties: componentProperties
                            )
                        ],
                        required: ["id", "component"]
                    ),
                    minItems: 1
                )
            ],
            required: [surfaceIdKey, "components"]
        )
    }
}
