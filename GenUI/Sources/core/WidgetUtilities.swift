//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import SwiftUI

/// SwiftUI helper that renders only when a value is non-nil.
/// Pairs a ValueNotifier<T?> with a content builder.
public struct OptionalValueBuilder<T, Content: View>: View {
    @ObservedObject private var notifier: ValueNotifier<T?>
    private let builder: (T) -> Content

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
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
/// Wraps a ValueNotifier<T> and exposes its value to a builder.
public struct ValueObserverView<T, Content: View>: View {
    @ObservedObject private var notifier: ValueNotifier<T>
    private let builder: (T) -> Content

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(listenable: ValueNotifier<T>, builder: @escaping (T) -> Content) {
        self.notifier = listenable
        self.builder = builder
    }

    public var body: some View {
        builder(notifier.value)
    }
}

/// Scoped view into the DataModel at a path.
/// Resolves relative paths for child widgets and subscriptions.
public extension DataContext {
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

    func subscribeToString(_ ref: JsonMap?) -> ValueNotifier<String?> {
        subscribeToValue(ref, literalKey: "literalString")
    }

    func subscribeToBool(_ ref: JsonMap?) -> ValueNotifier<Bool?> {
        subscribeToValue(ref, literalKey: "literalBoolean")
    }

    func subscribeToObjectArray(_ ref: JsonMap?) -> ValueNotifier<[Any]?> {
        subscribeToValue(ref, literalKey: "literalArray")
    }
}

/// Resolve context API.
/// Provides the public API for this declaration.
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
