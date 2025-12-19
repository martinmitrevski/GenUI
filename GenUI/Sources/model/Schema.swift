//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Enumerates JSON schema node types used by GenUI.
/// Matches the type strings in serialized schema payloads.
public enum SchemaType: String {
    case object
    case string
    case number
    case boolean
    case integer
    case array
    case any
}

/// Base class for schema nodes.
/// Stores type, title, and description metadata for serialization.
public class Schema {
    public let type: SchemaType
    public var title: String?
    public var description: String?

    /// Creates a schema node with optional metadata.
    /// Subclasses set the concrete type value.
    public init(type: SchemaType, title: String? = nil, description: String? = nil) {
        self.type = type
        self.title = title
        self.description = description
    }
}

/// Schema node describing an object shape.
/// Holds property schemas and required property names.
public final class ObjectSchema: Schema {
    public var properties: [String: Schema]
    public var required: [String]

    /// Creates an object schema with optional metadata.
    /// Provide properties and required keys as needed.
    public init(
        title: String? = nil,
        description: String? = nil,
        properties: [String: Schema] = [:],
        required: [String] = []
    ) {
        self.properties = properties
        self.required = required
        super.init(type: .object, title: title, description: description)
    }
}

/// Schema node describing an array/list.
/// Holds the item schema and optional minimum length.
public final class ListSchema: Schema {
    public var items: Schema?
    public var minItems: Int?

    /// Creates a list schema with optional items and size constraints.
    /// Use `minItems` to enforce a minimum length.
    public init(
        description: String? = nil,
        items: Schema? = nil,
        minItems: Int? = nil
    ) {
        self.items = items
        self.minItems = minItems
        super.init(type: .array, description: description)
    }
}

/// Schema node describing string values.
/// Optionally constrains the allowed enum values.
public final class StringSchema: Schema {
    public var enumValues: [String]?

    /// Creates a string schema with optional enum values.
    /// Provide a description to document the field.
    public init(description: String? = nil, enumValues: [String]? = nil) {
        self.enumValues = enumValues
        super.init(type: .string, description: description)
    }
}

/// Schema node describing numeric values.
/// Represents floating-point numbers.
public final class NumberSchema: Schema {
    /// Creates a number schema with optional description metadata.
    /// Use this for floating-point numeric values.
    public init(description: String? = nil) {
        super.init(type: .number, description: description)
    }
}

/// Schema node describing integer values.
/// Represents whole-number constraints.
public final class IntegerSchema: Schema {
    /// Creates an integer schema with optional description metadata.
    /// Use this for whole-number values.
    public init(description: String? = nil) {
        super.init(type: .integer, description: description)
    }
}

/// Schema node describing boolean values.
/// Represents true/false constraints.
public final class BooleanSchema: Schema {
    /// Creates a boolean schema with optional description metadata.
    /// Use this for true/false values.
    public init(description: String? = nil) {
        super.init(type: .boolean, description: description)
    }
}

/// Schema node describing unconstrained values.
/// Represents any JSON-compatible type.
public final class AnySchema: Schema {
    /// Creates an unconstrained schema node.
    /// Use this when the payload type can vary.
    public init(description: String? = nil) {
        super.init(type: .any, description: description)
    }
}

/// Factory namespace for schema helpers.
/// Provides concise builders for common schema node types.
public enum S {
    /// Builds an object schema.
    /// Provide properties and required keys as needed.
    public static func object(
        title: String? = nil,
        description: String? = nil,
        properties: [String: Schema] = [:],
        required: [String] = []
    ) -> ObjectSchema {
        ObjectSchema(title: title, description: description, properties: properties, required: required)
    }

    /// Builds a string schema.
    /// Optionally restricts to an enum of values.
    public static func string(
        description: String? = nil,
        enumValues: [String]? = nil
    ) -> StringSchema {
        StringSchema(description: description, enumValues: enumValues)
    }

    /// Builds a number schema.
    /// Represents floating-point numeric values.
    public static func number(description: String? = nil) -> NumberSchema {
        NumberSchema(description: description)
    }

    /// Builds an integer schema.
    /// Represents whole-number values.
    public static func integer(description: String? = nil) -> IntegerSchema {
        IntegerSchema(description: description)
    }

    /// Builds a boolean schema.
    /// Represents true/false values.
    public static func boolean(description: String? = nil) -> BooleanSchema {
        BooleanSchema(description: description)
    }

    /// Builds a list schema.
    /// Provide item schema and optional minimum size.
    public static func list(
        description: String? = nil,
        items: Schema? = nil,
        minItems: Int? = nil
    ) -> ListSchema {
        ListSchema(description: description, items: items, minItems: minItems)
    }

    /// Builds an unconstrained schema node.
    /// Represents any JSON-compatible value.
    public static func any(description: String? = nil) -> AnySchema {
        AnySchema(description: description)
    }
}
