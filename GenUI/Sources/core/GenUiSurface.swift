//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

/// SwiftUI view that renders a dynamic GenUI surface.
/// Builds a component tree from a `UiDefinition` and dispatches UI events.
public struct GenUiSurface: View {
    public let host: GenUiHost
    public let surfaceId: String
    public let defaultBuilder: (() -> AnyView)?

    @ObservedObject private var notifier: ValueNotifier<UiDefinition?>
    @State private var modalContent: AnyView = AnyView(EmptyView())
    @State private var isPresentingModal = false

    /// Creates a GenUI surface bound to a host and surface id.
    /// Provide a default view builder for empty or missing surfaces.
    public init(host: GenUiHost, surfaceId: String, defaultBuilder: (() -> AnyView)? = nil) {
        self.host = host
        self.surfaceId = surfaceId
        self.defaultBuilder = defaultBuilder
        self.notifier = host.getSurfaceNotifier(surfaceId)
    }

    public var body: some View {
        let definition = notifier.value

        return Group {
            if let definition {
                buildSurface(definition)
            } else {
                defaultBuilder?() ?? AnyView(EmptyView())
            }
        }
        .sheet(isPresented: $isPresentingModal) {
            modalContent
        }
    }

    private func buildSurface(_ definition: UiDefinition) -> AnyView {
        guard let rootId = definition.rootComponentId, !definition.components.isEmpty else {
            genUiLogger.warning("Surface \(surfaceId) has no widgets.")
            return AnyView(EmptyView())
        }

        guard let catalog = findCatalog(for: definition) else {
            return AnyView(EmptyView())
        }

        return buildWidget(
            definition: definition,
            catalog: catalog,
            widgetId: rootId,
            dataContext: DataContext(host.dataModelForSurface(surfaceId), "/")
        )
    }

    private func buildWidget(
        definition: UiDefinition,
        catalog: Catalog,
        widgetId: String,
        dataContext: DataContext
    ) -> AnyView {
        guard let data = definition.components[widgetId] else {
            genUiLogger.severe("Widget with id: \(widgetId) not found.")
            return AnyView(Text("Widget with id: \(widgetId) not found."))
        }

        let widgetData = data.componentProperties
        genUiLogger.finest("Building widget \(widgetId)")
        return catalog.buildWidget(
            CatalogItemContext(
                data: widgetData,
                id: widgetId,
                buildChild: { childId, childContext in
                    buildWidget(
                        definition: definition,
                        catalog: catalog,
                        widgetId: childId,
                        dataContext: childContext ?? dataContext
                    )
                },
                dispatchEvent: { event in
                    dispatchEvent(event, definition: definition, catalog: catalog)
                },
                buildContext: GenUiBuildContext(),
                dataContext: dataContext,
                getComponent: { componentId in
                    definition.components[componentId]
                },
                surfaceId: surfaceId
            )
        )
    }

    private func dispatchEvent(_ event: UiEventProtocol, definition: UiDefinition, catalog: Catalog) {
        if let action = event as? UserActionEvent, action.name == "showModal" {
            guard let modalId = action.context["modalId"] as? String,
                  let modalComponent = definition.components[modalId],
                  let modalProps = modalComponent.componentProperties["Modal"] as? JsonMap,
                  let contentChildId = modalProps["contentChild"] as? String else {
                return
            }

            modalContent = buildWidget(
                definition: definition,
                catalog: catalog,
                widgetId: contentChildId,
                dataContext: DataContext(host.dataModelForSurface(surfaceId), "/")
            )
            isPresentingModal = true
            return
        }

        var eventMap = event.toMap()
        eventMap[surfaceIdKey] = surfaceId
        if event is UserActionEvent {
            host.handleUiEvent(UserActionEvent(fromMap: eventMap))
        } else {
            host.handleUiEvent(UiEvent(fromMap: eventMap))
        }
    }

    private func findCatalog(for definition: UiDefinition) -> Catalog? {
        let catalogId = definition.catalogId ?? standardCatalogId
        let catalog = host.catalogs.first(where: { $0.catalogId == catalogId })

        if catalog == nil {
            genUiLogger.severe("Catalog with id \"\(catalogId)\" not found for surface \"\(surfaceId)\". Ensure the catalog is provided to A2uiMessageProcessor.")
        }
        return catalog
    }
}
