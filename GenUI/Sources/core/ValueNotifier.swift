//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import Combine

/// Type-erased interface for ValueNotifier.
/// Allows collections of heterogenous notifiers.
public protocol AnyValueNotifier: AnyObject {
    var currentValue: Any? { get }
    func setValue(_ value: Any?)
}

public final class ValueNotifier<T>: ObservableObject, AnyValueNotifier {
    @Published public var value: T

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(_ value: T) {
        self.value = value
    }

    public var currentValue: Any? {
        value
    }

    /// Set value API.
    /// Provides the public API for this declaration.
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
