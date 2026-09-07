//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Builders for the JSON Schema fragments used by A2UI catalog definitions.
///
/// A2UI catalogs are plain JSON Schema documents whose property types reference
/// the shared definitions in `common_types.json`. These helpers keep catalog
/// declarations readable while producing spec-compliant output that can be sent
/// to an agent as an inline catalog or embedded in a prompt.
public enum JsonSchema {
    /// The base URI of the shared A2UI common type definitions.
    public static let commonTypesUri = "https://a2ui.org/specification/v1_0/common_types.json"

    /// The JSON Schema dialect used by A2UI catalogs.
    public static let dialect = "https://json-schema.org/draft/2020-12/schema"

    // MARK: - Primitives

    /// Builds an object schema.
    /// Property order is irrelevant; `required` lists mandatory keys.
    public static func object(
        title: String? = nil,
        description: String? = nil,
        properties: [String: JsonMap] = [:],
        required: [String] = [],
        additionalProperties: Bool? = nil
    ) -> JsonMap {
        var schema: JsonMap = ["type": "object"]
        if let title { schema["title"] = title }
        if let description { schema["description"] = description }
        if !properties.isEmpty { schema["properties"] = properties }
        if !required.isEmpty { schema["required"] = required.sorted() }
        if let additionalProperties { schema["additionalProperties"] = additionalProperties }
        return schema
    }

    /// Builds a string schema.
    /// Use `enumValues` to constrain the accepted values.
    public static func string(
        description: String? = nil,
        enumValues: [String]? = nil,
        format: String? = nil,
        defaultValue: String? = nil
    ) -> JsonMap {
        var schema: JsonMap = ["type": "string"]
        if let description { schema["description"] = description }
        if let enumValues { schema["enum"] = enumValues }
        if let format { schema["format"] = format }
        if let defaultValue { schema["default"] = defaultValue }
        return schema
    }

    /// Builds a number schema.
    /// Use this for floating point properties such as layout weights.
    public static func number(description: String? = nil, defaultValue: Double? = nil) -> JsonMap {
        var schema: JsonMap = ["type": "number"]
        if let description { schema["description"] = description }
        if let defaultValue { schema["default"] = defaultValue }
        return schema
    }

    /// Builds an integer schema.
    /// Use `minimum` to constrain the accepted range.
    public static func integer(description: String? = nil, minimum: Int? = nil) -> JsonMap {
        var schema: JsonMap = ["type": "integer"]
        if let description { schema["description"] = description }
        if let minimum { schema["minimum"] = minimum }
        return schema
    }

    /// Builds a boolean schema.
    /// Use `defaultValue` to document the renderer's default behaviour.
    public static func boolean(description: String? = nil, defaultValue: Bool? = nil) -> JsonMap {
        var schema: JsonMap = ["type": "boolean"]
        if let description { schema["description"] = description }
        if let defaultValue { schema["default"] = defaultValue }
        return schema
    }

    /// Builds an array schema.
    /// Provide the item schema and optional minimum length.
    public static func array(description: String? = nil, items: JsonMap, minItems: Int? = nil) -> JsonMap {
        var schema: JsonMap = ["type": "array", "items": items]
        if let description { schema["description"] = description }
        if let minItems { schema["minItems"] = minItems }
        return schema
    }

    /// Builds a constant schema.
    /// Used for the `component` and `call` discriminators.
    public static func constant(_ value: String) -> JsonMap {
        ["const": value]
    }

    /// Builds a reference to another schema.
    /// Pass an absolute URI or a local JSON pointer.
    public static func reference(_ uri: String, description: String? = nil) -> JsonMap {
        var schema: JsonMap = ["$ref": uri]
        if let description { schema["description"] = description }
        return schema
    }

    /// Builds a schema accepting any of the given alternatives.
    public static func oneOf(_ schemas: [JsonMap], description: String? = nil) -> JsonMap {
        var schema: JsonMap = ["oneOf": schemas]
        if let description { schema["description"] = description }
        return schema
    }

    /// Builds a schema requiring all of the given fragments.
    public static func allOf(_ schemas: [JsonMap]) -> JsonMap {
        ["allOf": schemas]
    }

    // MARK: - A2UI common types

    /// A reference to a shared definition in `common_types.json`.
    public static func commonType(_ name: String, description: String? = nil) -> JsonMap {
        reference("\(commonTypesUri)#/$defs/\(name)", description: description)
    }

    /// A string that may be a literal, a data binding or a function call.
    public static func dynamicString(description: String? = nil) -> JsonMap {
        commonType("DynamicString", description: description)
    }

    /// A number that may be a literal, a data binding or a function call.
    public static func dynamicNumber(description: String? = nil) -> JsonMap {
        commonType("DynamicNumber", description: description)
    }

    /// A boolean that may be a literal, a data binding or a function call.
    public static func dynamicBoolean(description: String? = nil) -> JsonMap {
        commonType("DynamicBoolean", description: description)
    }

    /// A string array that may be a literal, a data binding or a function call.
    public static func dynamicStringList(description: String? = nil) -> JsonMap {
        commonType("DynamicStringList", description: description)
    }

    /// Any value that may be a literal, a data binding or a function call.
    public static func dynamicValue(description: String? = nil) -> JsonMap {
        commonType("DynamicValue", description: description)
    }

    /// A reference to a single child component id.
    public static func child(description: String? = nil) -> JsonMap {
        commonType("ComponentId", description: description)
    }

    /// A static list of child ids or a template bound to a collection.
    public static func children(description: String? = nil) -> JsonMap {
        commonType("ChildList", description: description)
    }

    /// An interaction handler that dispatches an event or calls a function.
    public static func action(description: String? = nil) -> JsonMap {
        commonType("Action", description: description)
    }

    /// The property set added to components that support validation checks.
    public static func checkable() -> JsonMap {
        commonType("Checkable")
    }

    /// The layout weight property shared by all basic catalog components.
    public static func weight() -> JsonMap {
        number(
            description: "The relative weight of this component within a Row or Column, similar to the CSS 'flex-grow' property. This may ONLY be set when the component is a direct descendant of a Row or Column."
        )
    }
}
