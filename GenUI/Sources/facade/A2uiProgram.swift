//
// Copyright © 2026 Martin Mitrevski. All rights reserved.
//

import Foundation

/// What is wrong with the A2UI messages of a reply, for a renderer with `catalog`: messages it
/// can't read, components it doesn't have, and references that lead nowhere.
///
/// An agent's instructions show it A2UI to write, which should render as it is: a broken example
/// teaches the model to write broken UI.
public enum A2uiProgram {
    /// The problems of the messages in `text`, or none when they render as written.
    public static func problems(in text: String, catalog: Catalog) -> [String] {
        var problems: [String] = []
        var surfaces: [String: [String: Component]] = [:]
        var order: [String] = []
        for raw in A2uiStream.messages(in: text) {
            guard let json = Json.decodeMap(raw) else {
                problems.append("this isn't JSON: \(raw.prefix(80))")
                continue
            }
            let message: A2uiMessage
            do {
                message = try A2uiMessageDecoder.decode(json)
            } catch {
                problems.append("\(error)")
                continue
            }
            switch message {
            case let .createSurface(created):
                if let catalogId = created.catalogId, catalogId != catalog.catalogId {
                    problems.append("surface \(created.surfaceId) names the catalog \(catalogId), not \(catalog.catalogId)")
                }
                surfaces[created.surfaceId] = Dictionary(created.components.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
                order.append(created.surfaceId)
            case let .updateComponents(update):
                guard surfaces[update.surfaceId] != nil else {
                    problems.append("surface \(update.surfaceId) gets components before it is created")
                    continue
                }
                for component in update.components {
                    surfaces[update.surfaceId]?[component.id] = component
                }
            case let .updateDataModel(update) where surfaces[update.surfaceId] == nil:
                problems.append("surface \(update.surfaceId) gets data before it is created")
            case .updateDataModel, .deleteSurface:
                break
            case .callRendererFunction, .agentFunctionResponse:
                problems.append("a reply's UI calls no functions")
            }
        }
        if order.isEmpty {
            problems.append("nothing renders: there is no createSurface")
        }
        for surfaceId in order {
            problems += self.problems(of: surfaces[surfaceId] ?? [:], on: surfaceId, catalog: catalog)
        }
        return problems
    }

    private static func problems(of components: [String: Component], on surfaceId: String, catalog: Catalog) -> [String] {
        var problems: [String] = []
        var references: [String: [String]] = [:]
        for component in components.values.sorted(by: { $0.id < $1.id }) {
            guard let definition = catalog.component(component.type) else {
                problems.append("\(component.id) is a \(component.type), which the catalog doesn't have")
                continue
            }
            for missing in definition.requiredProperties where component.properties[missing] == nil {
                problems.append("\(component.id) is a \(component.type) without its \(missing)")
            }
            let known = Set(definition.propertySchema.keys).union(["checks", "weight"])
            for property in component.properties.keys.sorted() where !known.contains(property) {
                problems.append("\(component.id) is a \(component.type), which has no \(property)")
            }
            references[component.id] = definition.propertySchema.flatMap { key, schema in
                ids(in: component.properties[key], schema: schema)
            }
        }
        for (id, children) in references.sorted(by: { $0.key < $1.key }) {
            for child in children where components[child] == nil {
                problems.append("\(id) holds \(child), which is not defined")
            }
        }
        guard components[A2uiProtocol.rootComponentId] != nil else {
            return problems + ["surface \(surfaceId) has no component with the id root"]
        }
        var reached: Set<String> = []
        var next = [A2uiProtocol.rootComponentId]
        while let id = next.popLast() {
            guard reached.insert(id).inserted else { continue }
            next += references[id] ?? []
        }
        for id in components.keys.sorted() where !reached.contains(id) {
            problems.append("\(id) is defined but nothing holds it")
        }
        return problems
    }

    // The component ids a property holds, found from the catalog's schema of it: a ComponentId,
    // a ChildList, or either one inside an array or an object, such as each of a Tabs' tabs.
    private static func ids(in value: Any?, schema: JsonMap) -> [String] {
        if let reference = schema["$ref"] as? String {
            if reference.hasSuffix("/ComponentId") {
                return (value as? String).map { [$0] } ?? []
            }
            if reference.hasSuffix("/ChildList") {
                switch ChildList(value) {
                case let .ids(ids): return ids
                case let .template(componentId, _): return [componentId]
                case .none: return []
                }
            }
        }
        if let items = Json.map(schema["items"]), let array = Json.array(value) {
            return array.flatMap { ids(in: $0, schema: items) }
        }
        if let properties = Json.map(schema["properties"]), let object = Json.map(value) {
            return properties.keys.sorted().flatMap { key in
                Json.map(properties[key]).map { ids(in: object[key], schema: $0) } ?? []
            }
        }
        return []
    }
}
