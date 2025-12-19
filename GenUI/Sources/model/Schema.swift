//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Enumeration of JSON schema types used by the builder.
/// Maps to common schema type strings.
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
/// Stores type, title, and description metadata.
public class Schema {
    public let type: SchemaType
    public var title: String?
    public var description: String?

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(type: SchemaType, title: String? = nil, description: String? = nil) {
        self.type = type
        self.title = title
        self.description = description
    }
}

public final class ObjectSchema: Schema {
    public var properties: [String: Schema]
    public var required: [String]

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
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

public final class ListSchema: Schema {
    public var items: Schema?
    public var minItems: Int?

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
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

public final class StringSchema: Schema {
    public var enumValues: [String]?

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(description: String? = nil, enumValues: [String]? = nil) {
        self.enumValues = enumValues
        super.init(type: .string, description: description)
    }
}

public final class NumberSchema: Schema {
    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(description: String? = nil) {
        super.init(type: .number, description: description)
    }
}

public final class IntegerSchema: Schema {
    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(description: String? = nil) {
        super.init(type: .integer, description: description)
    }
}

public final class BooleanSchema: Schema {
    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(description: String? = nil) {
        super.init(type: .boolean, description: description)
    }
}

public final class AnySchema: Schema {
    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(description: String? = nil) {
        super.init(type: .any, description: description)
    }
}

/// Factory namespace for schema helpers.
/// Provides convenience builders for common schema types.
public enum S {
    public static func object(
        title: String? = nil,
        description: String? = nil,
        properties: [String: Schema] = [:],
        required: [String] = []
    ) -> ObjectSchema {
        ObjectSchema(title: title, description: description, properties: properties, required: required)
    }

    public static func string(
        description: String? = nil,
        enumValues: [String]? = nil
    ) -> StringSchema {
        StringSchema(description: description, enumValues: enumValues)
    }

    public static func number(description: String? = nil) -> NumberSchema {
        NumberSchema(description: description)
    }

    public static func integer(description: String? = nil) -> IntegerSchema {
        IntegerSchema(description: description)
    }

    public static func boolean(description: String? = nil) -> BooleanSchema {
        BooleanSchema(description: description)
    }

    public static func list(
        description: String? = nil,
        items: Schema? = nil,
        minItems: Int? = nil
    ) -> ListSchema {
        ListSchema(description: description, items: items, minItems: minItems)
    }

    public static func any(description: String? = nil) -> AnySchema {
        AnySchema(description: description)
    }
}
