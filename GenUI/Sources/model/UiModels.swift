//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Sends a batch of UI events for a surface.
/// Provides the surface id and the collected events.
public typealias SendEventsCallback = (String, [UiEventProtocol]) -> Void
/// Dispatches a single UI event.
/// Used by widgets to report user interactions.
public typealias DispatchEventCallback = (UiEventProtocol) -> Void

/// Protocol describing a UI event payload.
/// Exposes surface metadata and a JSON serialization hook.
public protocol UiEventProtocol {
    var surfaceId: String { get }
    var widgetId: String { get }
    var eventType: String { get }
    var isAction: Bool { get }
    var value: Any? { get }
    var timestamp: Date { get }
    func toMap() -> JsonMap
}

/// Concrete UI event backed by a JSON map.
/// Provides typed accessors to standard event fields.
public struct UiEvent: UiEventProtocol {
    private let json: JsonMap

    /// Wraps an existing event payload.
    /// Use this to provide typed access over a JSON map.
    public init(fromMap json: JsonMap) {
        self.json = json
    }

    public var surfaceId: String { json[surfaceIdKey] as? String ?? "" }
    public var widgetId: String { json["widgetId"] as? String ?? "" }
    public var eventType: String { json["eventType"] as? String ?? "" }
    public var isAction: Bool { json["isAction"] as? Bool ?? false }
    public var value: Any? { json["value"] }

    public var timestamp: Date {
        if let string = json["timestamp"] as? String,
           let date = ISO8601DateFormatter().date(from: string) {
            return date
        }
        return Date()
    }

    /// Returns the underlying JSON payload.
    /// Use this when serializing events for transport.
    public func toMap() -> JsonMap { json }
}

/// Event representing a user-triggered action.
/// Includes action name, source component id, and optional context.
public struct UserActionEvent: UiEventProtocol {
    private let json: JsonMap

    /// Creates a user action event payload.
    /// Use this when emitting button taps or similar actions.
    public init(
        surfaceId: String? = nil,
        name: String,
        sourceComponentId: String,
        timestamp: Date? = nil,
        context: JsonMap? = nil
    ) {
        var json: JsonMap = [
            "name": name,
            "sourceComponentId": sourceComponentId,
            "timestamp": ISO8601DateFormatter().string(from: timestamp ?? Date()),
            "isAction": true,
            "context": context ?? [:]
        ]
        if let surfaceId {
            json[surfaceIdKey] = surfaceId
        }
        self.json = json
    }

    /// Wraps an existing action payload.
    /// Use this when parsing action events from JSON.
    public init(fromMap json: JsonMap) {
        self.json = json
    }

    public var surfaceId: String { json[surfaceIdKey] as? String ?? "" }
    public var widgetId: String { json["widgetId"] as? String ?? "" }
    public var eventType: String { json["eventType"] as? String ?? "" }
    public var isAction: Bool { json["isAction"] as? Bool ?? true }
    public var value: Any? { json["value"] }

    public var timestamp: Date {
        if let string = json["timestamp"] as? String,
           let date = ISO8601DateFormatter().date(from: string) {
            return date
        }
        return Date()
    }

    public var name: String { json["name"] as? String ?? "" }
    public var sourceComponentId: String { json["sourceComponentId"] as? String ?? "" }
    public var context: JsonMap { json["context"] as? JsonMap ?? [:] }

    /// Returns the underlying JSON payload.
    /// Use this when serializing events for transport.
    public func toMap() -> JsonMap { json }
}

/// Snapshot of a rendered surface and its components.
/// Holds root id, catalog id, styles, and component map.
public struct UiDefinition {
    public let surfaceId: String
    public let rootComponentId: String?
    public let catalogId: String?
    public let styles: JsonMap?

    public var components: [String: Component] { _components }
    private let _components: [String: Component]

    /// Creates a UI definition snapshot.
    /// Provide surface metadata and component map.
    public init(
        surfaceId: String,
        rootComponentId: String? = nil,
        catalogId: String? = nil,
        components: [String: Component] = [:],
        styles: JsonMap? = nil
    ) {
        self.surfaceId = surfaceId
        self.rootComponentId = rootComponentId
        self.catalogId = catalogId
        self._components = components
        self.styles = styles
    }

    /// Copies the definition while overriding selected fields.
    /// Omitted parameters keep their existing values.
    public func copyWith(
        rootComponentId: String? = nil,
        catalogId: String? = nil,
        components: [String: Component]? = nil,
        styles: JsonMap? = nil
    ) -> UiDefinition {
        UiDefinition(
            surfaceId: surfaceId,
            rootComponentId: rootComponentId ?? self.rootComponentId,
            catalogId: catalogId ?? self.catalogId,
            components: components ?? self._components,
            styles: styles ?? self.styles
        )
    }

    /// Serializes the definition to a JSON map.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        [
            surfaceIdKey: surfaceId,
            "rootComponentId": rootComponentId as Any,
            "components": _components.mapValues { $0.toJson() }
        ]
    }

    /// Formats the UI definition as context text.
    /// Useful when describing the current UI to an LLM.
    public func asContextDescriptionText() -> String {
        let payload = toJson()
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
              let text = String(data: data, encoding: .utf8) else {
            return "A user interface is shown with the following content: {}."
        }
        return "A user interface is shown with the following content:\n\(text)."
    }
}

/// A single UI component instance in a surface.
/// Stores component id, properties, and optional layout weight.
public struct Component: Equatable {
    public let id: String
    public let componentProperties: JsonMap
    public let weight: Int?

    /// Creates a component instance.
    /// Provide the id, component properties, and optional weight.
    public init(id: String, componentProperties: JsonMap, weight: Int? = nil) {
        self.id = id
        self.componentProperties = componentProperties
        self.weight = weight
    }

    /// Parses a component definition from a JSON map.
    /// Handles missing component properties by returning an empty map.
    public static func fromJson(_ json: JsonMap) -> Component {
        guard let component = json["component"] as? JsonMap else {
            return Component(id: json["id"] as? String ?? "", componentProperties: [:])
        }
        return Component(
            id: json["id"] as? String ?? "",
            componentProperties: component,
            weight: json["weight"] as? Int
        )
    }

    /// Serializes the component to a JSON map.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        var json: JsonMap = ["id": id, "component": componentProperties]
        if let weight {
            json["weight"] = weight
        }
        return json
    }

    public var type: String {
        componentProperties.keys.first ?? ""
    }

    /// Compares two components by id, weight, and properties.
    /// Uses dictionary equality for component properties.
    public static func == (lhs: Component, rhs: Component) -> Bool {
        let lhsMap = NSDictionary(dictionary: lhs.componentProperties)
        return lhs.id == rhs.id && lhs.weight == rhs.weight && lhsMap.isEqual(to: rhs.componentProperties)
    }
}
