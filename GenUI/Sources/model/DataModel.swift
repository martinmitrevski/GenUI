//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Represents a path inside the GenUI data model.
/// Supports absolute or relative addressing and path composition.
public struct DataPath: Hashable, CustomStringConvertible {
    public let segments: [String]
    public let isAbsolute: Bool

    public static let root = DataPath(segments: [], isAbsolute: true)
    private static let separator = "/"

    /// Parses a string path into segments.
    /// Leading `/` marks the path as absolute.
    public init(_ path: String) {
        let segments = path
            .split(separator: Character(Self.separator))
            .map { String($0) }
            .filter { !$0.isEmpty }
        self.segments = segments
        self.isAbsolute = path.hasPrefix(Self.separator)
    }

    private init(segments: [String], isAbsolute: Bool) {
        self.segments = segments
        self.isAbsolute = isAbsolute
    }

    public var basename: String {
        segments.last ?? ""
    }

    public var dirname: DataPath {
        guard !segments.isEmpty else { return self }
        return DataPath(segments: Array(segments.dropLast()), isAbsolute: isAbsolute)
    }

    /// Joins another path onto this one.
    /// Absolute paths replace the current path.
    public func join(_ other: DataPath) -> DataPath {
        if other.isAbsolute { return other }
        return DataPath(segments: segments + other.segments, isAbsolute: isAbsolute)
    }

    /// Checks whether this path begins with another path.
    /// Useful for deciding whether updates affect a subtree.
    public func startsWith(_ other: DataPath) -> Bool {
        guard other.segments.count <= segments.count else { return false }
        for (index, segment) in other.segments.enumerated() {
            if segments[index] != segment { return false }
        }
        return true
    }

    public var description: String {
        let path = segments.joined(separator: Self.separator)
        return isAbsolute ? "\(Self.separator)\(path)" : path
    }
}

/// Scoped view into a `DataModel` rooted at a path.
/// Resolves relative paths and exposes subscriptions to values.
public final class DataContext {
    private let dataModel: DataModel
    public let path: DataPath

    /// Creates a data context rooted at the provided path.
    /// The path may be absolute or relative to the model root.
    public init(_ dataModel: DataModel, _ path: String) {
        self.dataModel = dataModel
        self.path = DataPath(path)
    }

    private init(dataModel: DataModel, path: DataPath) {
        self.dataModel = dataModel
        self.path = path
    }

    /// Subscribes to a path relative to this context.
    /// Returns a notifier that updates when the value changes.
    public func subscribe<T>(_ relativeOrAbsolutePath: DataPath) -> ValueNotifier<T?> {
        let absolutePath = resolvePath(relativeOrAbsolutePath)
        return dataModel.subscribe(absolutePath)
    }

    /// Reads a value relative to this context.
    /// Returns nil if the resolved path is missing.
    public func getValue<T>(_ relativeOrAbsolutePath: DataPath) -> T? {
        let absolutePath = resolvePath(relativeOrAbsolutePath)
        return dataModel.getValue(absolutePath)
    }

    /// Updates a value relative to this context.
    /// Notifies subscribers for affected paths.
    public func update(_ relativeOrAbsolutePath: DataPath, _ contents: Any?) {
        let absolutePath = resolvePath(relativeOrAbsolutePath)
        dataModel.update(absolutePath: absolutePath, contents: contents)
    }

    /// Creates a nested context for a child path.
    /// The returned context resolves paths under the new root.
    public func nested(_ relativePath: DataPath) -> DataContext {
        let newPath = resolvePath(relativePath)
        return DataContext(dataModel: dataModel, path: newPath)
    }

    /// Resolves a path relative to this context.
    /// Absolute paths are returned unchanged.
    public func resolvePath(_ pathToResolve: DataPath) -> DataPath {
        if pathToResolve.isAbsolute { return pathToResolve }
        return path.join(pathToResolve)
    }
}

/// Stores key-value data for dynamic UI components.
/// Supports path subscriptions and incremental updates.
public final class DataModel {
    private var data: JsonMap = [:]
    private var subscriptions: [DataPath: AnyValueNotifier] = [:]
    private var valueSubscriptions: [DataPath: AnyValueNotifier] = [:]

    /// Creates an empty data model.
    /// Use `update` to populate data.
    public init() {}

    public var snapshot: JsonMap {
        data
    }

    /// Updates the data model at a given absolute path.
    /// Notifies subscribers for affected paths.
    public func update(absolutePath: DataPath?, contents: Any?) {
        genUiLogger.info("DataModel.update: path=\(String(describing: absolutePath)), contents=\(String(describing: contents))")

        guard let absolutePath, !absolutePath.segments.isEmpty else {
            if let list = contents as? [Any] {
                data = parseDataModelContents(list)
            } else if let map = contents as? JsonMap {
                genUiLogger.info("DataModel.update: contents for root path is a Map, not a List: \(map)")
                data = map
            } else {
                genUiLogger.warning("DataModel.update: contents for root path is not a List or Map: \(String(describing: contents))")
                data = [:]
            }
            notifySubscribers(path: .root)
            return
        }

        var current: Any = data
        updateValue(current: &current, segments: absolutePath.segments, value: contents)
        if let updated = current as? JsonMap {
            data = updated
        }
        notifySubscribers(path: absolutePath)
    }

    /// Subscribes to an absolute path.
    /// Returns a notifier that updates when the value changes.
    public func subscribe<T>(_ absolutePath: DataPath) -> ValueNotifier<T?> {
        genUiLogger.info("DataModel.subscribe: path=\(absolutePath)")
        let initialValue: T? = getValue(absolutePath)

        if let existing = subscriptions[absolutePath] as? ValueNotifier<T?> {
            Task { @MainActor in
                existing.value = initialValue
            }
            return existing
        }

        let notifier = ValueNotifier<T?>(initialValue)
        subscriptions[absolutePath] = notifier
        return notifier
    }

    /// Subscribes to a path with literal fallback support.
    /// Initializes the notifier with the current path value.
    public func subscribeToValue<T>(_ absolutePath: DataPath) -> ValueNotifier<T?> {
        genUiLogger.info("DataModel.subscribeToValue: path=\(absolutePath)")
        let initialValue: T? = getValue(absolutePath)

        if let existing = valueSubscriptions[absolutePath] as? ValueNotifier<T?> {
            existing.value = initialValue
            return existing
        }

        let notifier = ValueNotifier<T?>(initialValue)
        valueSubscriptions[absolutePath] = notifier
        return notifier
    }

    /// Reads a value at an absolute path.
    /// Returns nil if the path is missing.
    public func getValue<T>(_ absolutePath: DataPath) -> T? {
        getValue(current: data, segments: absolutePath.segments) as? T
    }

    private func parseDataModelContents(_ contents: [Any]) -> JsonMap {
        var newData: JsonMap = [:]
        for item in contents {
            guard let itemMap = item as? JsonMap, let key = itemMap["key"] as? String else {
                genUiLogger.warning("Invalid item in dataModelUpdate contents: \(item)")
                continue
            }

            let valueKeys = ["valueString", "valueNumber", "valueBoolean", "valueMap"]
            var value: Any?
            var valueCount = 0

            for valueKey in valueKeys {
                guard itemMap.keys.contains(valueKey) else { continue }
                if valueCount == 0 {
                    if valueKey == "valueMap" {
                        if let list = itemMap[valueKey] as? [Any] {
                            value = parseDataModelContents(list)
                        } else {
                            genUiLogger.warning("valueMap for key \"\(key)\" is not a List: \(String(describing: itemMap[valueKey]))")
                        }
                    } else {
                        value = itemMap[valueKey]
                    }
                }
                valueCount += 1
            }

            if valueCount == 0 {
                genUiLogger.warning("No value field found for key \"\(key)\" in contents: \(itemMap)")
            } else if valueCount > 1 {
                genUiLogger.warning("Multiple value fields found for key \"\(key)\" in contents: \(itemMap). Using the first one found.")
            }
            newData[key] = value
        }
        return newData
    }

    private func getValue(current: Any?, segments: [String]) -> Any? {
        guard let segment = segments.first else {
            return current
        }

        let remaining = Array(segments.dropFirst())

        if let map = current as? JsonMap {
            return getValue(current: map[segment], segments: remaining)
        }
        if let list = current as? [Any], let index = Int(segment), index >= 0, index < list.count {
            return getValue(current: list[index], segments: remaining)
        }
        return nil
    }

    private func updateValue(current: inout Any, segments: [String], value: Any?) {
        guard let segment = segments.first else { return }
        let remaining = Array(segments.dropFirst())

        if var map = current as? JsonMap {
            if remaining.isEmpty {
                map[segment] = value
                current = map
                return
            }

            var nextNode = map[segment]
            if nextNode == nil {
                let nextSegment = remaining.first ?? ""
                let isNextSegmentListIndex = Int(nextSegment) != nil
                nextNode = isNextSegmentListIndex ? [Any]() : JsonMap()
                map[segment] = nextNode
            }

            var updatedNode: Any = nextNode as Any
            updateValue(current: &updatedNode, segments: remaining, value: value)
            map[segment] = updatedNode
            current = map
            return
        }

        if var list = current as? [Any], let index = Int(segment), index >= 0 {
            if remaining.isEmpty {
                if index < list.count {
                    list[index] = value as Any
                } else if index == list.count {
                    list.append(value as Any)
                } else {
                    return
                }
                current = list
                return
            }

            if index < list.count {
                var child: Any = list[index]
                updateValue(current: &child, segments: remaining, value: value)
                list[index] = child
                current = list
                return
            }

            if index == list.count {
                let nextSegment = remaining.first ?? ""
                let shouldCreateList = Int(nextSegment) != nil
                let newNode: Any = shouldCreateList ? [Any]() : JsonMap()
                list.append(newNode)
                var child: Any = newNode
                updateValue(current: &child, segments: remaining, value: value)
                list[index] = child
                current = list
                return
            }

            return
        }
    }

    private func notifySubscribers(path: DataPath) {
        genUiLogger.info("DataModel.notifySubscribers: notifying \(subscriptions.count) subscribers for path=\(path)")
        for (subscriptionPath, notifier) in subscriptions {
            if subscriptionPath.startsWith(path) || path.startsWith(subscriptionPath) {
                genUiLogger.info("  - Notifying subscriber for path=\(subscriptionPath)")
                notifier.setValue(getValue(subscriptionPath))
            }
        }

        if let notifier = valueSubscriptions[path] {
            genUiLogger.info("  - Notifying value subscriber for path=\(path)")
            notifier.setValue(getValue(path))
        }
    }
}
