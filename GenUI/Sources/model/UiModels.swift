//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Callback invoked when UI events are batched.
/// Provides the surface id and event list.
public typealias SendEventsCallback = (String, [UiEventProtocol]) -> Void
/// Callback invoked for a single UI event.
/// Used by catalog widgets to send interactions.
public typealias DispatchEventCallback = (UiEventProtocol) -> Void

/// Protocol for UI event payloads.
/// Defines required fields for surface and widget events.
public protocol UiEventProtocol {
    var surfaceId: String { get }
    var widgetId: String { get }
    var eventType: String { get }
    var isAction: Bool { get }
    var value: Any? { get }
    var timestamp: Date { get }
    func toMap() -> JsonMap
}

/// Concrete event wrapper backed by a JsonMap.
/// Provides typed accessors to event fields.
public struct UiEvent: UiEventProtocol {
    private let json: JsonMap

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
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

    /// To map API.
    /// Provides the public API for this declaration.
    public func toMap() -> JsonMap { json }
}

/// Event representing a user-triggered action.
/// Includes action name, source id, and optional context.
public struct UserActionEvent: UiEventProtocol {
    private let json: JsonMap

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
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

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
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

    /// To map API.
    /// Provides the public API for this declaration.
    public func toMap() -> JsonMap { json }
}

/// Snapshot of a rendered surface and its components.
/// Holds the root component id, catalog id, and component map.
public struct UiDefinition {
    public let surfaceId: String
    public let rootComponentId: String?
    public let catalogId: String?
    public let styles: JsonMap?

    public var components: [String: Component] { _components }
    private let _components: [String: Component]

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
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

    /// Creates a copy with updated fields.
    /// Unspecified values fall back to the original instance.
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

    /// Serializes the value to a JSON-compatible dictionary.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        [
            surfaceIdKey: surfaceId,
            "rootComponentId": rootComponentId as Any,
            "components": _components.mapValues { $0.toJson() }
        ]
    }

    /// Formats the UI definition as context text.
    /// Used to describe the UI to language models.
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
/// Stores the component id, properties, and optional layout weight.
public struct Component: Equatable {
    public let id: String
    public let componentProperties: JsonMap
    public let weight: Int?

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(id: String, componentProperties: JsonMap, weight: Int? = nil) {
        self.id = id
        self.componentProperties = componentProperties
        self.weight = weight
    }

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

    /// Serializes the value to a JSON-compatible dictionary.
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

    public static func == (lhs: Component, rhs: Component) -> Bool {
        let lhsMap = NSDictionary(dictionary: lhs.componentProperties)
        return lhs.id == rhs.id && lhs.weight == rhs.weight && lhsMap.isEqual(to: rhs.componentProperties)
    }
}
