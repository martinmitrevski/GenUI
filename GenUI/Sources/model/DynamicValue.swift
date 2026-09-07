//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// A component property value as it arrives on the wire.
///
/// A2UI properties declared as `DynamicString`, `DynamicNumber`,
/// `DynamicBoolean`, `DynamicStringList` or `DynamicValue` accept one of three
/// shapes: a literal, a data binding (`{"path": "/a/b"}`) or a function call
/// (`{"call": "formatString", "args": {...}}`).
public enum DynamicValue: Equatable {
    /// A literal JSON value.
    case literal(Any)

    /// A data binding to a possibly relative path.
    case binding(DataPath)

    /// A function call evaluated by the renderer or routed to the agent.
    case function(FunctionCall)

    /// The property was absent.
    case missing

    /// Classifies a raw JSON value into a dynamic value.
    /// Objects are treated as bindings or calls only when they carry `path` or `call`.
    public init(_ raw: Any?) {
        guard let raw = Json.normalized(raw) else {
            self = .missing
            return
        }
        if let map = raw as? JsonMap {
            if let call = FunctionCall(map) {
                self = .function(call)
                return
            }
            if map.count == 1, let path = map["path"] as? String {
                self = .binding(DataPath(path))
                return
            }
        }
        self = .literal(raw)
    }

    /// Whether the property was absent on the wire.
    public var isMissing: Bool {
        if case .missing = self { return true }
        return false
    }

    /// The binding path, when this value is a data binding.
    public var bindingPath: DataPath? {
        if case let .binding(path) = self { return path }
        return nil
    }

    /// The literal value, when this value is a literal.
    public var literalValue: Any? {
        if case let .literal(value) = self { return value }
        return nil
    }

    /// The wire representation of this value.
    /// Round-trips a decoded property back to JSON.
    public var rawValue: Any? {
        switch self {
        case let .literal(value): return value
        case let .binding(path): return ["path": path.description]
        case let .function(call): return call.rawValue
        case .missing: return nil
        }
    }

    /// Compares two dynamic values structurally.
    /// Literals are compared as JSON.
    public static func == (lhs: DynamicValue, rhs: DynamicValue) -> Bool {
        switch (lhs, rhs) {
        case (.missing, .missing):
            return true
        case let (.binding(left), .binding(right)):
            return left == right
        case let (.function(left), .function(right)):
            return left == right
        case let (.literal(left), .literal(right)):
            return Json.isEqual(left, right)
        default:
            return false
        }
    }
}

/// A named function invocation embedded in a component tree.
///
/// Functions are resolved against the catalog identified by `catalogId`, or the
/// surface default catalog when the call does not declare one. Names starting
/// with `@` are universal system functions.
public struct FunctionCall: Equatable {
    /// The name of the function to call.
    public let name: String

    /// The catalog that defines the function, when explicitly declared.
    public let catalogId: String?

    /// The raw, unevaluated arguments of the call.
    public let arguments: JsonMap

    /// Creates a function call.
    /// Arguments stay unevaluated so that nested bindings resolve lazily.
    public init(name: String, catalogId: String? = nil, arguments: JsonMap = [:]) {
        self.name = name
        self.catalogId = catalogId
        self.arguments = arguments
    }

    /// Parses a function call from a JSON object.
    /// Returns `nil` when the object does not carry a `call` property.
    public init?(_ json: JsonMap) {
        guard let name = json["call"] as? String else { return nil }
        self.name = name
        self.catalogId = json["catalogId"] as? String
        self.arguments = Json.map(json["args"]) ?? [:]
    }

    /// Whether this is a universal system function such as `@index`.
    public var isSystemFunction: Bool {
        name.hasPrefix(A2uiProtocol.systemFunctionPrefix)
    }

    /// The wire representation of the call.
    public var rawValue: JsonMap {
        var json: JsonMap = ["call": name]
        if let catalogId { json["catalogId"] = catalogId }
        if !arguments.isEmpty { json["args"] = arguments }
        return json
    }

    /// Compares two calls by name, catalog and arguments.
    public static func == (lhs: FunctionCall, rhs: FunctionCall) -> Bool {
        lhs.name == rhs.name
            && lhs.catalogId == rhs.catalogId
            && Json.isEqual(lhs.arguments, rhs.arguments)
    }
}

/// The children of a container component.
///
/// A2UI containers either list their children explicitly or declare a template
/// that is instantiated once per item of a bound collection.
public enum ChildList: Equatable {
    /// A static list of component ids.
    case ids([String])

    /// A template instantiated for every item at `path`.
    case template(componentId: String, path: DataPath)

    /// No children were declared.
    case none

    /// Parses a child list from a raw property value.
    /// Accepts both the array and template object forms.
    public init(_ raw: Any?) {
        guard let raw = Json.normalized(raw) else {
            self = .none
            return
        }
        if let ids = Json.stringArray(raw) {
            self = .ids(ids)
            return
        }
        if let map = raw as? JsonMap,
           let componentId = map["componentId"] as? String,
           let path = map["path"] as? String {
            self = .template(componentId: componentId, path: DataPath(path))
            return
        }
        self = .none
    }

    /// The statically declared child ids, if any.
    public var staticIds: [String] {
        if case let .ids(ids) = self { return ids }
        return []
    }
}

/// The interaction handler of an interactive component.
///
/// An action either dispatches a named event to the agent or executes a
/// function locally on the renderer.
public enum ActionDefinition: Equatable {
    /// Dispatches an event to the agent.
    case event(EventAction)

    /// Executes a function call.
    case functionCall(FunctionCall)

    /// Parses an action from a raw property value.
    /// Returns `nil` when neither `event` nor `functionCall` is present.
    public init?(_ raw: Any?) {
        guard let map = Json.map(raw) else { return nil }
        if let event = Json.map(map["event"]), let action = EventAction(event) {
            self = .event(action)
            return
        }
        if let call = Json.map(map["functionCall"]), let function = FunctionCall(call) {
            self = .functionCall(function)
            return
        }
        return nil
    }
}

/// An agent-bound event dispatched by a component.
public struct EventAction: Equatable {
    /// The event name reported to the agent.
    public let name: String

    /// An optional human-readable description of what the user did.
    public let userMessage: DynamicValue

    /// Context values sent with the event, keyed by name.
    public let context: [String: DynamicValue]

    /// Creates an event action.
    /// Context values may be literals, bindings or function calls.
    public init(name: String, userMessage: DynamicValue = .missing, context: [String: DynamicValue] = [:]) {
        self.name = name
        self.userMessage = userMessage
        self.context = context
    }

    /// Parses an event action from a JSON object.
    /// Returns `nil` when the required `name` is missing.
    public init?(_ json: JsonMap) {
        guard let name = json["name"] as? String else { return nil }
        self.name = name
        self.userMessage = DynamicValue(json["userMessage"])
        self.context = (Json.map(json["context"]) ?? [:]).mapValues { DynamicValue($0) }
    }
}

/// A single renderer-side validation rule.
public struct CheckRule: Equatable {
    /// A binding or function call evaluating to a ``ValidationResult``.
    public let condition: DynamicValue

    /// A fallback message shown when the condition fails without one.
    public let message: String?

    /// Creates a check rule.
    /// The condition is evaluated whenever the component renders.
    public init(condition: DynamicValue, message: String? = nil) {
        self.condition = condition
        self.message = message
    }

    /// Parses a check rule from a JSON object.
    /// Returns `nil` when the condition is missing.
    public init?(_ json: JsonMap) {
        let condition = DynamicValue(json["condition"])
        guard !condition.isMissing else { return nil }
        self.condition = condition
        self.message = json["message"] as? String
    }

    /// Parses a list of check rules from a raw property value.
    /// Invalid entries are skipped.
    public static func list(_ raw: Any?) -> [CheckRule] {
        (Json.array(raw) ?? []).compactMap { entry in
            guard let map = Json.map(entry) else { return nil }
            return CheckRule(map)
        }
    }
}

/// The outcome of a renderer-side validation rule.
public struct ValidationResult: Equatable {
    /// How serious a failed check is.
    public enum Severity: String {
        case error
        case warning
        case info
    }

    /// Whether the check passed.
    public let isValid: Bool

    /// An optional machine-readable failure code.
    public let code: String?

    /// An optional human-readable message.
    public let message: String?

    /// How serious the failure is.
    public let severity: Severity

    /// Creates a validation result.
    /// Failures should carry a message so the UI can explain them.
    public init(isValid: Bool, code: String? = nil, message: String? = nil, severity: Severity = .error) {
        self.isValid = isValid
        self.code = code
        self.message = message
        self.severity = severity
    }

    /// A passing result.
    public static let valid = ValidationResult(isValid: true)

    /// Creates a failing result with a message.
    /// Use this from validation function implementations.
    public static func invalid(_ message: String, code: String? = nil) -> ValidationResult {
        ValidationResult(isValid: false, code: code, message: message)
    }

    /// Coerces an evaluated value into a validation result.
    ///
    /// Booleans are treated as pass/fail so that logical functions such as
    /// `and` can be used directly as check conditions, and `nil` (a pending or
    /// unresolved value) is treated as passing so progressive rendering does
    /// not block the user.
    public init(coercing value: Any?) {
        guard let value = Json.normalized(value) else {
            self = .valid
            return
        }
        if let map = value as? JsonMap, let isValid = Json.bool(map["valid"]) {
            self = ValidationResult(
                isValid: isValid,
                code: map["code"] as? String,
                message: map["message"] as? String,
                severity: Severity(rawValue: Json.string(map["severity"]) ?? "") ?? .error
            )
            return
        }
        self = ValidationResult(isValid: Json.bool(value) ?? true)
    }

    /// The wire representation of the result.
    public var rawValue: JsonMap {
        var json: JsonMap = ["valid": isValid]
        if let code { json["code"] = code }
        if let message { json["message"] = message }
        json["severity"] = severity.rawValue
        return json
    }
}

/// Accessibility metadata attached to any component.
///
/// These values are mapped onto the platform accessibility APIs and override
/// the semantics inferred from the component's visible content.
public struct AccessibilityAttributes: Equatable {
    /// How dynamic updates should be announced.
    public enum Live: String {
        case off
        case polite
        case assertive
    }

    /// A short label describing the element's purpose.
    public let label: DynamicValue

    /// Additional instructions or result information.
    public let description: DynamicValue

    /// How updates to this element are announced.
    public let live: Live

    /// Whether the element is hidden from assistive technologies.
    public let hidden: DynamicValue

    /// Creates accessibility attributes.
    /// All values are optional and may be data bound.
    public init(
        label: DynamicValue = .missing,
        description: DynamicValue = .missing,
        live: Live = .off,
        hidden: DynamicValue = .missing
    ) {
        self.label = label
        self.description = description
        self.live = live
        self.hidden = hidden
    }

    /// Parses accessibility attributes from a JSON object.
    /// Returns `nil` when no attributes are present.
    public init?(_ raw: Any?) {
        guard let json = Json.map(raw), !json.isEmpty else { return nil }
        self.init(
            label: DynamicValue(json["label"]),
            description: DynamicValue(json["description"]),
            live: Live(rawValue: Json.string(json["live"]) ?? "") ?? .off,
            hidden: DynamicValue(json["hidden"])
        )
    }

    /// The wire representation of the attributes.
    public var rawValue: JsonMap {
        var json: JsonMap = [:]
        if let label = label.rawValue { json["label"] = label }
        if let description = description.rawValue { json["description"] = description }
        if live != .off { json["live"] = live.rawValue }
        if let hidden = hidden.rawValue { json["hidden"] = hidden }
        return json
    }
}
