//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import GenUI

/// Concise builders for the A2UI components the sample agent emits.
///
/// Agents normally generate JSON with a model; the sample agent builds the same
/// structures in Swift so its output is deterministic and easy to test.
public enum A2ui {
    /// Builds a component of any type.
    /// Properties are passed through to the wire payload unchanged.
    public static func component(_ id: String, _ type: String, _ properties: JsonMap = [:]) -> Component {
        Component(id: id, type: type, properties: properties)
    }

    /// A data binding to a data model path.
    public static func path(_ path: String) -> JsonMap {
        ["path": path]
    }

    /// A function call with named arguments.
    public static func call(_ name: String, _ arguments: JsonMap = [:]) -> JsonMap {
        arguments.isEmpty ? ["call": name] : ["call": name, "args": arguments]
    }

    /// A `formatString` call, the catalog's string interpolation function.
    public static func format(_ template: String) -> JsonMap {
        call("formatString", ["value": template])
    }

    /// A `formatCurrency` call.
    public static func currency(_ value: Any, code: String = "USD") -> JsonMap {
        call("formatCurrency", ["value": value, "currency": code])
    }

    /// An event action dispatched to the agent.
    public static func event(_ name: String, userMessage: Any? = nil, context: JsonMap = [:]) -> JsonMap {
        var event: JsonMap = ["name": name, "context": context]
        if let userMessage { event["userMessage"] = userMessage }
        return ["event": event]
    }

    /// A validation check with an optional custom message.
    public static func check(_ condition: JsonMap, message: String? = nil) -> JsonMap {
        var check: JsonMap = ["condition": condition]
        if let message { check["message"] = message }
        return check
    }

    /// A `Text` component.
    public static func text(_ id: String, _ value: Any, variant: String? = nil, weight: Double? = nil) -> Component {
        var properties: JsonMap = ["text": value]
        if let variant { properties["variant"] = variant }
        if let weight { properties["weight"] = weight }
        return component(id, "Text", properties)
    }

    /// A `Column` layout component.
    public static func column(
        _ id: String,
        _ children: Any,
        align: String? = nil,
        justify: String? = nil,
        weight: Double? = nil
    ) -> Component {
        var properties: JsonMap = ["children": children]
        if let align { properties["align"] = align }
        if let justify { properties["justify"] = justify }
        if let weight { properties["weight"] = weight }
        return component(id, "Column", properties)
    }

    /// A `Row` layout component.
    public static func row(
        _ id: String,
        _ children: Any,
        align: String? = nil,
        justify: String? = nil,
        weight: Double? = nil
    ) -> Component {
        var properties: JsonMap = ["children": children]
        if let align { properties["align"] = align }
        if let justify { properties["justify"] = justify }
        if let weight { properties["weight"] = weight }
        return component(id, "Row", properties)
    }

    /// A `Card` container with a single child.
    public static func card(_ id: String, child: String) -> Component {
        component(id, "Card", ["child": child])
    }

    /// A `List` container, either static or template driven.
    public static func list(_ id: String, _ children: Any, direction: String? = nil) -> Component {
        var properties: JsonMap = ["children": children]
        if let direction { properties["direction"] = direction }
        return component(id, "List", properties)
    }

    /// A template child list bound to a data model collection.
    public static func template(_ componentId: String, path: String) -> JsonMap {
        ["componentId": componentId, "path": path]
    }

    /// An `Image` component.
    public static func image(_ id: String, url: Any, variant: String? = nil, fit: String? = nil, description: Any? = nil) -> Component {
        var properties: JsonMap = ["url": url]
        if let variant { properties["variant"] = variant }
        if let fit { properties["fit"] = fit }
        if let description { properties["description"] = description }
        return component(id, "Image", properties)
    }

    /// An `Icon` component.
    public static func icon(_ id: String, _ name: String) -> Component {
        component(id, "Icon", ["name": name])
    }

    /// A `Button` component.
    public static func button(
        _ id: String,
        child: String,
        action: JsonMap,
        variant: String? = nil,
        checks: [JsonMap] = []
    ) -> Component {
        var properties: JsonMap = ["child": child, "action": action]
        if let variant { properties["variant"] = variant }
        if !checks.isEmpty { properties["checks"] = checks }
        return component(id, "Button", properties)
    }

    /// A `Divider` component.
    public static func divider(_ id: String) -> Component {
        component(id, "Divider")
    }

    /// A `TextField` input component.
    public static func textField(
        _ id: String,
        label: Any,
        value: JsonMap,
        placeholder: Any? = nil,
        variant: String? = nil,
        checks: [JsonMap] = []
    ) -> Component {
        var properties: JsonMap = ["label": label, "value": value]
        if let placeholder { properties["placeholder"] = placeholder }
        if let variant { properties["variant"] = variant }
        if !checks.isEmpty { properties["checks"] = checks }
        return component(id, "TextField", properties)
    }

    /// A `CheckBox` input component.
    public static func checkBox(_ id: String, label: Any, value: JsonMap) -> Component {
        component(id, "CheckBox", ["label": label, "value": value])
    }

    /// A `ChoicePicker` input component.
    public static func choicePicker(
        _ id: String,
        label: Any? = nil,
        options: [JsonMap],
        value: JsonMap,
        variant: String? = nil,
        displayStyle: String? = nil,
        checks: [JsonMap] = []
    ) -> Component {
        var properties: JsonMap = ["options": options, "value": value]
        if let label { properties["label"] = label }
        if let variant { properties["variant"] = variant }
        if let displayStyle { properties["displayStyle"] = displayStyle }
        if !checks.isEmpty { properties["checks"] = checks }
        return component(id, "ChoicePicker", properties)
    }

    /// A `DateTimeInput` component.
    public static func dateTimeInput(
        _ id: String,
        label: Any,
        value: JsonMap,
        enableDate: Bool = true,
        enableTime: Bool = true,
        checks: [JsonMap] = []
    ) -> Component {
        var properties: JsonMap = [
            "label": label,
            "value": value,
            "enableDate": enableDate,
            "enableTime": enableTime
        ]
        if !checks.isEmpty { properties["checks"] = checks }
        return component(id, "DateTimeInput", properties)
    }
}
