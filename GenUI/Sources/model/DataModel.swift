//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// The mutable state backing a single A2UI surface.
///
/// The data model is a plain JSON object addressed with ``DataPath`` pointers.
/// Agents replace or patch it with `updateDataModel` messages, and input
/// components write to it directly as the user interacts with them.
///
/// Instances are not thread-safe. The renderer always mutates them from the
/// main actor, which is also where SwiftUI reads them.
public final class DataModel {
    /// A change to the data model, reported to observers.
    public struct Change {
        /// The absolute path that was written.
        public let path: DataPath

        /// The value written at `path`, or `nil` when the value was removed.
        public let value: Any?
    }

    private var storage: JsonMap
    private var observers: [UUID: (Change) -> Void] = [:]

    /// Creates a data model with an optional initial value.
    /// Pass the `dataModel` payload of a `createSurface` message here.
    public init(_ initialValue: JsonMap = [:]) {
        self.storage = initialValue
    }

    /// The current contents of the data model.
    /// Use this when synchronizing state back to the agent.
    public var snapshot: JsonMap {
        storage
    }

    /// Registers an observer that is notified after every write.
    /// Call the returned closure to stop observing.
    @discardableResult
    public func observe(_ observer: @escaping (Change) -> Void) -> () -> Void {
        let token = UUID()
        observers[token] = observer
        return { [weak self] in
            self?.observers.removeValue(forKey: token)
        }
    }

    /// Reads the value at an absolute path.
    /// Returns `nil` when the path does not exist.
    public func value(at path: DataPath) -> Any? {
        Json.normalized(Self.read(storage, segments: path.segments))
    }

    /// Reads and coerces the value at an absolute path.
    /// Coercion follows the A2UI type conversion rules.
    public func string(at path: DataPath) -> String? { Json.string(value(at: path)) }

    /// Writes a value at an absolute path, creating intermediate containers.
    ///
    /// Passing `nil` (or JSON `null`) removes the entry at `path`, matching the
    /// upsert semantics defined by the specification. Writing to the root path
    /// replaces the whole data model.
    public func update(at path: DataPath, value: Any?) {
        let newValue = Json.normalized(value)

        guard !path.segments.isEmpty else {
            storage = Json.map(newValue) ?? [:]
            notify(Change(path: .root, value: storage))
            return
        }

        var root: Any = storage
        Self.write(&root, segments: path.segments, value: newValue)
        storage = root as? JsonMap ?? storage
        notify(Change(path: path, value: newValue))
    }

    /// Replaces the entire data model.
    /// Equivalent to writing to the root path.
    public func replaceAll(with value: JsonMap) {
        update(at: .root, value: value)
    }

    private func notify(_ change: Change) {
        for observer in observers.values {
            observer(change)
        }
    }

    // MARK: - Traversal

    private static func read(_ current: Any?, segments: [String]) -> Any? {
        guard let segment = segments.first else { return current }
        let remaining = Array(segments.dropFirst())

        if let map = current as? JsonMap {
            return read(map[segment], segments: remaining)
        }
        if let list = current as? JsonArray, let index = Int(segment), index >= 0, index < list.count {
            return read(list[index], segments: remaining)
        }
        return nil
    }

    private static func write(_ current: inout Any, segments: [String], value: Any?) {
        guard let segment = segments.first else { return }
        let remaining = Array(segments.dropFirst())

        if var map = current as? JsonMap {
            if remaining.isEmpty {
                if let value {
                    map[segment] = value
                } else {
                    map.removeValue(forKey: segment)
                }
                current = map
                return
            }

            var child: Any = map[segment] ?? emptyContainer(forNextSegment: remaining[0])
            write(&child, segments: remaining, value: value)
            map[segment] = child
            current = map
            return
        }

        if var list = current as? JsonArray, let index = Int(segment), index >= 0 {
            if remaining.isEmpty {
                if let value {
                    if index < list.count {
                        list[index] = value
                    } else if index == list.count {
                        list.append(value)
                    } else {
                        return
                    }
                } else if index < list.count {
                    list.remove(at: index)
                }
                current = list
                return
            }

            if index < list.count {
                var child: Any = list[index]
                write(&child, segments: remaining, value: value)
                list[index] = child
                current = list
                return
            }

            if index == list.count {
                var child: Any = emptyContainer(forNextSegment: remaining[0])
                write(&child, segments: remaining, value: value)
                list.append(child)
                current = list
            }
            return
        }

        // The existing value is a scalar (or missing): replace it with a container.
        var replacement: Any = emptyContainer(forNextSegment: segment)
        write(&replacement, segments: segments, value: value)
        current = replacement
    }

    private static func emptyContainer(forNextSegment segment: String) -> Any {
        Int(segment) != nil ? JsonArray() : JsonMap()
    }
}
