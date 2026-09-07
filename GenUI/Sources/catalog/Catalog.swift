//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import SwiftUI

/// Builds the SwiftUI view for one component instance.
/// The context exposes the component's resolved properties and children.
public typealias ComponentViewBuilder = (ComponentRenderContext) -> AnyView

/// A component type the renderer knows how to build.
///
/// A definition carries both halves of a catalog entry: the JSON Schema the
/// agent is told to generate against, and the SwiftUI builder that renders it.
public struct ComponentDefinition {
    /// The component type name, used as the `component` discriminator.
    public let name: String

    /// A human-readable description included in the catalog schema.
    public let description: String?

    /// The JSON Schema of the component's own properties.
    public let propertySchema: [String: JsonMap]

    /// The property names the agent must always provide.
    public let requiredProperties: [String]

    /// Parent component types allowed to contain this component.
    ///
    /// `nil` allows any parent. Use `["Surface"]` to restrict a component to
    /// the top level of a surface.
    public let allowedParents: [String]?

    /// Child component types this container accepts.
    /// `nil` allows any child.
    public let allowedChildren: [String]?

    /// Example message payloads used by the debug gallery.
    public let examples: [String]

    /// Renders one instance of the component.
    public let builder: ComponentViewBuilder

    /// Creates a component definition.
    /// The `component` discriminator is added to the schema automatically.
    public init(
        name: String,
        description: String? = nil,
        properties: [String: JsonMap] = [:],
        required: [String] = [],
        allowedParents: [String]? = nil,
        allowedChildren: [String]? = nil,
        examples: [String] = [],
        builder: @escaping ComponentViewBuilder
    ) {
        self.name = name
        self.description = description
        self.propertySchema = properties
        self.requiredProperties = required
        self.allowedParents = allowedParents
        self.allowedChildren = allowedChildren
        self.examples = examples
        self.builder = builder
    }

    /// The full JSON Schema of the component, as it appears in a catalog.
    /// Includes the `component` const discriminator required by the spec.
    public var schema: JsonMap {
        var properties = propertySchema
        properties["component"] = JsonSchema.constant(name)
        var schema = JsonSchema.object(
            description: description,
            properties: properties,
            required: (requiredProperties + ["component"]).sorted()
        )
        if let allowedParents { schema["allowedParents"] = allowedParents }
        if let allowedChildren { schema["allowedChildren"] = allowedChildren }
        return schema
    }
}

/// A function the renderer can evaluate, or that the agent may invoke.
public struct FunctionDefinition {
    /// The type of value a function returns.
    public enum ReturnType: String {
        case string
        case number
        case boolean
        case array
        case object
        case validationResult
        case any
        case void
    }

    /// Which side of the connection may invoke a function.
    public enum AllowedCallers: String {
        /// Only the renderer, for example from a component binding.
        case rendererOnly
        /// Only the agent, through `callRendererFunction`.
        case agentOnly
        /// Both sides.
        case rendererOrAgent
    }

    /// The function name referenced by `call`.
    public let name: String

    /// A human-readable description included in the catalog schema.
    public let description: String

    /// The JSON Schema of the function's `args` object.
    public let argumentsSchema: JsonMap?

    /// The type of value the function returns.
    public let returnType: ReturnType

    /// Which side of the connection may invoke the function.
    public let allowedCallers: AllowedCallers

    /// Whether the function needs a user activation context, such as a tap.
    public let requiresUserActivation: Bool

    /// The renderer-side implementation.
    public let implementation: A2uiFunctionImplementation

    /// Creates a function definition.
    /// Functions that require user activation must be `rendererOnly`.
    public init(
        name: String,
        description: String,
        arguments: JsonMap? = nil,
        returnType: ReturnType,
        allowedCallers: AllowedCallers = .rendererOnly,
        requiresUserActivation: Bool = false,
        implementation: @escaping A2uiFunctionImplementation
    ) {
        self.name = name
        self.description = description
        self.argumentsSchema = arguments
        self.returnType = returnType
        self.allowedCallers = requiresUserActivation ? .rendererOnly : allowedCallers
        self.requiresUserActivation = requiresUserActivation
        self.implementation = implementation
    }

    /// Whether the agent is allowed to invoke this function remotely.
    public var isAgentCallable: Bool {
        allowedCallers == .agentOnly || allowedCallers == .rendererOrAgent
    }

    /// Whether the renderer may evaluate this function from a component tree.
    public var isRendererCallable: Bool {
        allowedCallers == .rendererOnly || allowedCallers == .rendererOrAgent
    }

    /// The full JSON Schema of the function, as it appears in a catalog.
    /// Includes the `call` const discriminator required by the spec.
    public var schema: JsonMap {
        var properties: JsonMap = ["call": JsonSchema.constant(name)]
        var required = ["call"]
        if let argumentsSchema {
            properties["args"] = argumentsSchema
            required.append("args")
        }
        var schema: JsonMap = [
            "type": "object",
            "description": description,
            "returnType": returnType.rawValue,
            "allowedCallers": allowedCallers.rawValue,
            "properties": properties,
            "required": required
        ]
        if requiresUserActivation {
            schema["requiresUserActivation"] = true
        }
        return schema
    }
}

/// A set of component and function definitions a renderer supports.
///
/// The catalog id is an opaque identifier that renderer and agent must agree
/// on. It is conventionally a URI, but it is never resolved over the network.
public struct Catalog {
    /// The unique identifier of this catalog.
    public let catalogId: String

    /// A short title for the catalog.
    public let title: String?

    /// A human-readable description of the catalog.
    public let description: String?

    /// Markdown design guidelines that steer agents generating for this catalog.
    public let instructions: String?

    /// The components of the catalog, keyed by type name.
    public let components: [String: ComponentDefinition]

    /// The functions of the catalog, keyed by function name.
    public let functions: [String: FunctionDefinition]

    /// Creates a catalog from component and function definitions.
    /// Duplicate names are resolved in favour of the last definition.
    public init(
        catalogId: String,
        title: String? = nil,
        description: String? = nil,
        instructions: String? = nil,
        components: [ComponentDefinition] = [],
        functions: [FunctionDefinition] = []
    ) {
        self.catalogId = catalogId
        self.title = title
        self.description = description
        self.instructions = instructions
        self.components = Dictionary(components.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
        self.functions = Dictionary(functions.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
    }

    /// Looks up a component definition by type name.
    /// Returns `nil` when this catalog does not define the component.
    public func component(_ name: String) -> ComponentDefinition? {
        components[name]
    }

    /// Looks up a function definition by name.
    /// Returns `nil` when this catalog does not define the function.
    public func function(_ name: String) -> FunctionDefinition? {
        functions[name]
    }

    /// Returns a copy with additional components and functions.
    /// Use this to extend the basic catalog with app-specific components.
    public func adding(
        components newComponents: [ComponentDefinition] = [],
        functions newFunctions: [FunctionDefinition] = [],
        catalogId: String? = nil,
        instructions: String? = nil
    ) -> Catalog {
        Catalog(
            catalogId: catalogId ?? self.catalogId,
            title: title,
            description: description,
            instructions: instructions ?? self.instructions,
            components: Array(components.values) + newComponents,
            functions: Array(functions.values) + newFunctions
        )
    }

    /// Returns a copy without the named components.
    /// Use this to hide components an app does not want agents to use.
    public func removing(components names: [String], catalogId: String? = nil) -> Catalog {
        let removed = Set(names)
        return Catalog(
            catalogId: catalogId ?? self.catalogId,
            title: title,
            description: description,
            instructions: instructions,
            components: components.values.filter { !removed.contains($0.name) },
            functions: Array(functions.values)
        )
    }

    /// The catalog serialized as an A2UI v1.0 catalog definition document.
    ///
    /// Send this to agents as an inline catalog, or embed it in a prompt when
    /// driving an LLM directly.
    public func toJsonSchema() -> JsonMap {
        var componentSchemas: JsonMap = [:]
        for (name, definition) in components {
            componentSchemas[name] = definition.schema
        }
        var functionSchemas: JsonMap = [:]
        for (name, definition) in functions {
            functionSchemas[name] = definition.schema
        }

        var schema: JsonMap = [
            "$schema": JsonSchema.dialect,
            "$id": catalogId,
            "protocolVersion": "1.0",
            "catalogId": catalogId
        ]
        if let title { schema["title"] = title }
        if let description { schema["description"] = description }
        if let instructions { schema["instructions"] = instructions }
        if !componentSchemas.isEmpty { schema["components"] = componentSchemas }
        if !functionSchemas.isEmpty { schema["functions"] = functionSchemas }
        schema["$defs"] = [
            "anyComponent": [
                "oneOf": components.keys.sorted().map { ["$ref": "#/components/\($0)"] },
                "discriminator": ["propertyName": "component"]
            ] as JsonMap,
            "anyFunction": [
                "oneOf": functions.keys.sorted().map { ["$ref": "#/functions/\($0)"] }
            ] as JsonMap
        ] as JsonMap
        return schema
    }
}

/// Resolves components and functions across all catalogs a renderer supports.
///
/// Resolution follows the order defined by the specification: an explicit
/// component or function level `catalogId` wins, then the surface default
/// catalog. There is deliberately no fallback to "any supported catalog".
public struct CatalogRegistry {
    /// The catalogs available to the renderer, keyed by catalog id.
    public let catalogs: [String: Catalog]

    /// A renderer-configured catalog used when a surface declares none.
    ///
    /// The specification requires a surface default; this optional value keeps
    /// the renderer usable with agents that omit `catalogId`.
    public let defaultCatalogId: String?

    /// Creates a registry from the catalogs a renderer supports.
    /// Pass `defaultCatalogId` to tolerate agents that omit the surface catalog.
    public init(catalogs: [Catalog], defaultCatalogId: String? = nil) {
        self.catalogs = Dictionary(catalogs.map { ($0.catalogId, $0) }, uniquingKeysWith: { _, last in last })
        self.defaultCatalogId = defaultCatalogId
    }

    /// The ids of all supported catalogs, sorted for stable capability payloads.
    public var supportedCatalogIds: [String] {
        catalogs.keys.sorted()
    }

    /// Looks up a catalog by id.
    /// Returns `nil` when the catalog is not supported.
    public func catalog(_ catalogId: String?) -> Catalog? {
        guard let catalogId else { return nil }
        return catalogs[catalogId]
    }

    /// Resolves the catalog that applies to an entity.
    /// Falls back from the entity level id to the surface default.
    public func resolveCatalog(entityCatalogId: String?, surfaceCatalogId: String?) -> Catalog? {
        if let catalog = catalog(entityCatalogId) { return catalog }
        if entityCatalogId != nil { return nil }
        if let catalog = catalog(surfaceCatalogId) { return catalog }
        if surfaceCatalogId != nil { return nil }
        return catalog(defaultCatalogId)
    }

    /// Resolves a component definition for a component instance.
    /// Returns `nil` when neither the component nor the surface names a known catalog.
    public func component(_ component: Component, surfaceCatalogId: String?) -> ComponentDefinition? {
        resolveCatalog(entityCatalogId: component.catalogId, surfaceCatalogId: surfaceCatalogId)?
            .component(component.type)
    }

    /// Resolves a function definition for a function call.
    /// Returns `nil` when the function is not defined in the resolved catalog.
    public func function(_ call: FunctionCall, surfaceCatalogId: String?) -> FunctionDefinition? {
        resolveCatalog(entityCatalogId: call.catalogId, surfaceCatalogId: surfaceCatalogId)?
            .function(call.name)
    }

    /// Finds a function by name in any supported catalog.
    ///
    /// Used for agent-initiated `callRendererFunction` messages, which carry an
    /// explicit catalog id but may target a catalog the surface does not use.
    public func function(named name: String, catalogId: String?) -> FunctionDefinition? {
        if let catalogId {
            return catalogs[catalogId]?.function(name)
        }
        for id in supportedCatalogIds {
            if let function = catalogs[id]?.function(name) { return function }
        }
        return nil
    }
}
