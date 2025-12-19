//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import SwiftUI

/// SwiftUI helper that renders only when a value is non-nil.
/// Observes a `ValueNotifier<T?>` and builds content when available.
public struct OptionalValueBuilder<T, Content: View>: View {
    @ObservedObject private var notifier: ValueNotifier<T?>
    private let builder: (T) -> Content

    /// Creates a builder driven by a nullable value notifier.
    /// The builder is invoked only when a value is present.
    public init(listenable: ValueNotifier<T?>, builder: @escaping (T) -> Content) {
        self.notifier = listenable
        self.builder = builder
    }

    public var body: some View {
        if let value = notifier.value {
            builder(value)
        } else {
            EmptyView()
        }
    }
}

/// SwiftUI helper that rebuilds on value changes.
/// Observes a `ValueNotifier<T>` and feeds its current value to a builder.
public struct ValueObserverView<T, Content: View>: View {
    @ObservedObject private var notifier: ValueNotifier<T>
    private let builder: (T) -> Content

    /// Creates a view that rebuilds when the notifier changes.
    /// The builder receives the current value each update.
    public init(listenable: ValueNotifier<T>, builder: @escaping (T) -> Content) {
        self.notifier = listenable
        self.builder = builder
    }

    public var body: some View {
        builder(notifier.value)
    }
}

/// Convenience subscriptions for data-bound widget values.
/// Resolves data model paths and falls back to literal values.
public extension DataContext {
    /// Subscribes to a reference object with a literal fallback.
    /// Uses `literalKey` when no path is provided.
    func subscribeToValue<T>(_ ref: JsonMap?, literalKey: String) -> ValueNotifier<T?> {
        genUiLogger.info("DataContext.subscribeToValue: ref=\(String(describing: ref)), literalKey=\(literalKey)")
        guard let ref else { return ValueNotifier<T?>(nil) }
        let path = ref["path"] as? String
        let literal = ref[literalKey]

        if let path {
            let dataPath = DataPath(path)
            if let literal {
                update(dataPath, literal)
            }
            return subscribe(dataPath)
        }

        return ValueNotifier<T?>(literal as? T)
    }

    /// Subscribes to a string reference with literal fallback.
    /// Expects the `literalString` key when no path is provided.
    func subscribeToString(_ ref: JsonMap?) -> ValueNotifier<String?> {
        subscribeToValue(ref, literalKey: "literalString")
    }

    /// Subscribes to a boolean reference with literal fallback.
    /// Expects the `literalBoolean` key when no path is provided.
    func subscribeToBool(_ ref: JsonMap?) -> ValueNotifier<Bool?> {
        subscribeToValue(ref, literalKey: "literalBoolean")
    }

    /// Subscribes to an array reference with literal fallback.
    /// Expects the `literalArray` key when no path is provided.
    func subscribeToObjectArray(_ ref: JsonMap?) -> ValueNotifier<[Any]?> {
        subscribeToValue(ref, literalKey: "literalArray")
    }
}

/// Resolves action context bindings against the data model.
/// Converts path-based entries into literal values.
public func resolveContext(_ dataContext: DataContext, _ contextDefinitions: [Any]) -> JsonMap {
    var resolved: JsonMap = [:]
    for contextEntry in contextDefinitions {
        guard let entry = contextEntry as? JsonMap,
              let key = entry["key"] as? String,
              let value = entry["value"] as? JsonMap else { continue }

        if let path = value["path"] as? String {
            resolved[key] = dataContext.getValue(DataPath(path))
        } else if value["literalString"] != nil {
            resolved[key] = value["literalString"]
        } else if value["literalNumber"] != nil {
            resolved[key] = value["literalNumber"]
        } else if value["literalBoolean"] != nil {
            resolved[key] = value["literalBoolean"]
        }
    }
    return resolved
}
