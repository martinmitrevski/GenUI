//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import Combine

/// Type-erased interface for `ValueNotifier` values.
/// Allows collections of heterogeneous notifiers.
public protocol AnyValueNotifier: AnyObject {
    var currentValue: Any? { get }
    func setValue(_ value: Any?)
}

/// Observable container that publishes value changes.
/// Used to drive SwiftUI updates from data model changes.
public final class ValueNotifier<T>: ObservableObject, AnyValueNotifier {
    @Published public var value: T

    /// Creates a notifier with an initial value.
    /// The value is published to SwiftUI observers.
    public init(_ value: T) {
        self.value = value
    }

    public var currentValue: Any? {
        value
    }

    /// Sets the value using a type-erased payload.
    /// Ignores values that cannot be cast to `T`.
    public func setValue(_ value: Any?) {
        if let cast = value as? T {
            self.value = cast
            return
        }
        if value == nil, let nilValue = Optional<Any>.none as? T {
            self.value = nilValue
        }
    }
}
