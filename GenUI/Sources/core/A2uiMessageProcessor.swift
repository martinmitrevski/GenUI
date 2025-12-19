//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import Combine

/// Marker protocol for surface update notifications.
/// Implemented by add/update/remove events emitted by the processor.
public protocol GenUiUpdate {
    var surfaceId: String { get }
}

/// Notification emitted when a surface is created.
/// Includes the surface id and the initial `UiDefinition`.
public struct SurfaceAdded: GenUiUpdate {
    public let surfaceId: String
    public let definition: UiDefinition

    /// Creates a surface-added update.
    /// Includes the surface id and initial definition.
    public init(surfaceId: String, definition: UiDefinition) {
        self.surfaceId = surfaceId
        self.definition = definition
    }
}

/// Notification emitted when a surface changes.
/// Includes the surface id and updated `UiDefinition`.
public struct SurfaceUpdated: GenUiUpdate {
    public let surfaceId: String
    public let definition: UiDefinition

    /// Creates a surface-updated notification.
    /// Includes the surface id and updated definition.
    public init(surfaceId: String, definition: UiDefinition) {
        self.surfaceId = surfaceId
        self.definition = definition
    }
}

/// Notification emitted when a surface is deleted.
/// Includes the surface id that was removed.
public struct SurfaceRemoved: GenUiUpdate {
    public let surfaceId: String

    /// Creates a surface-removed notification.
    /// Includes the surface id that was removed.
    public init(surfaceId: String) {
        self.surfaceId = surfaceId
    }
}

/// Interface for hosting dynamic UI surfaces.
/// Provides surface streams, catalogs, and event handling.
public protocol GenUiHost {
    var surfaceUpdates: AnyPublisher<GenUiUpdate, Never> { get }

    /// Returns a notifier for a surface definition.
    /// The notifier updates when the surface definition changes.
    func getSurfaceNotifier(_ surfaceId: String) -> ValueNotifier<UiDefinition?>

    var catalogs: [Catalog] { get }
    var dataModels: [String: DataModel] { get }

    /// Returns the data model for the given surface id.
    /// Implementations may lazily create missing models.
    func dataModelForSurface(_ surfaceId: String) -> DataModel

    /// Handles UI events emitted by rendered surfaces.
    /// Hosts may forward events to agents or analytics.
    func handleUiEvent(_ event: UiEventProtocol)
}

/// Processes A2UI messages and maintains surface state.
/// Acts as a `GenUiHost` for rendered surfaces.
public final class A2uiMessageProcessor: GenUiHost {
    public let catalogs: [Catalog]

    private var surfaces: [String: ValueNotifier<UiDefinition?>] = [:]
    private let surfaceUpdatesSubject = PassthroughSubject<GenUiUpdate, Never>()
    private let onSubmitSubject = PassthroughSubject<UserUiInteractionMessage, Never>()
    private var dataModelsInternal: [String: DataModel] = [:]

    /// Creates a message processor with the provided catalogs.
    /// Catalogs are used to render component definitions.
    public init(catalogs: [Catalog]) {
        self.catalogs = catalogs
    }

    public var dataModels: [String: DataModel] {
        dataModelsInternal
    }

    /// Returns the data model for a surface.
    /// Creates a new model if one does not exist.
    public func dataModelForSurface(_ surfaceId: String) -> DataModel {
        if let existing = dataModelsInternal[surfaceId] {
            return existing
        }
        let model = DataModel()
        dataModelsInternal[surfaceId] = model
        return model
    }

    public var surfaceUpdates: AnyPublisher<GenUiUpdate, Never> {
        surfaceUpdatesSubject.eraseToAnyPublisher()
    }

    public var onSubmit: AnyPublisher<UserUiInteractionMessage, Never> {
        onSubmitSubject.eraseToAnyPublisher()
    }

    /// Handles a UI event from a surface.
    /// Emits user interaction messages when needed.
    public func handleUiEvent(_ event: UiEventProtocol) {
        guard let actionEvent = event as? UserActionEvent else { return }
        let messageJson: JsonMap = ["userAction": actionEvent.toMap()]
        if let data = try? JSONSerialization.data(withJSONObject: messageJson, options: []),
           let string = String(data: data, encoding: .utf8) {
            onSubmitSubject.send(UserUiInteractionMessage.text(string))
        }
    }

    /// Returns a notifier for a surface definition.
    /// Creates a new notifier if the surface is unknown.
    public func getSurfaceNotifier(_ surfaceId: String) -> ValueNotifier<UiDefinition?> {
        if surfaces[surfaceId] == nil {
            genUiLogger.fine("Adding new surface \(surfaceId)")
        } else {
            genUiLogger.fine("Fetching surface notifier for \(surfaceId)")
        }
        let notifier = surfaces[surfaceId] ?? ValueNotifier<UiDefinition?>(nil)
        surfaces[surfaceId] = notifier
        return notifier
    }

    /// Releases cached surfaces and data models.
    /// Call when the processor is no longer needed.
    public func dispose() {
        surfaces.removeAll()
        dataModelsInternal.removeAll()
    }

    /// Processes an incoming A2UI message.
    /// Updates surfaces, data models, and update streams.
    public func handleMessage(_ message: A2uiMessage) {
        switch message {
        case let update as SurfaceUpdate:
            let surfaceId = update.surfaceId
            let notifier = getSurfaceNotifier(surfaceId)

            var uiDefinition = notifier.value ?? UiDefinition(surfaceId: surfaceId)
            var newComponents = uiDefinition.components
            for component in update.components {
                newComponents[component.id] = component
            }
            uiDefinition = uiDefinition.copyWith(components: newComponents)
            notifier.value = uiDefinition

            if uiDefinition.rootComponentId != nil {
                genUiLogger.info("Updating surface \(surfaceId)")
                surfaceUpdatesSubject.send(SurfaceUpdated(surfaceId: surfaceId, definition: uiDefinition))
            } else {
                genUiLogger.info("Caching components for surface \(surfaceId) (pre-rendering)")
            }
        case let begin as BeginRendering:
            let surfaceId = begin.surfaceId
            _ = dataModelForSurface(surfaceId)
            let notifier = getSurfaceNotifier(surfaceId)

            let uiDefinition = notifier.value ?? UiDefinition(surfaceId: surfaceId)
            let newDefinition = uiDefinition.copyWith(
                rootComponentId: begin.root,
                catalogId: begin.catalogId
            )
            notifier.value = newDefinition

            genUiLogger.info("Creating and rendering surface \(surfaceId)")
            surfaceUpdatesSubject.send(SurfaceAdded(surfaceId: surfaceId, definition: newDefinition))
        case let update as DataModelUpdate:
            let path = update.path ?? "/"
            genUiLogger.info("Updating data model for surface \(update.surfaceId) at path \(path) with contents: \(String(describing: update.contents))")
            let model = dataModelForSurface(update.surfaceId)
            model.update(absolutePath: DataPath(path), contents: update.contents)

            let notifier = getSurfaceNotifier(update.surfaceId)
            if let definition = notifier.value, definition.rootComponentId != nil {
                surfaceUpdatesSubject.send(SurfaceUpdated(surfaceId: update.surfaceId, definition: definition))
            }
        case let deletion as SurfaceDeletion:
            let surfaceId = deletion.surfaceId
            if surfaces[surfaceId] != nil {
                genUiLogger.info("Deleting surface \(surfaceId)")
                surfaces.removeValue(forKey: surfaceId)
                dataModelsInternal.removeValue(forKey: surfaceId)
                surfaceUpdatesSubject.send(SurfaceRemoved(surfaceId: surfaceId))
            }
        default:
            break
        }
    }
}
