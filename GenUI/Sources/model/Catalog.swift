//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import SwiftUI

/// Catalog of UI components available to the renderer.
/// Builds widgets from component data and exposes a schema description.
public struct Catalog {
    public let items: [CatalogItem]
    public let catalogId: String?

    /// Creates a catalog with optional id metadata.
    /// Provide the catalog items in renderable order.
    public init(_ items: [CatalogItem], catalogId: String? = nil) {
        self.items = items
        self.catalogId = catalogId
    }

    /// Merges new items into the catalog.
    /// Items with matching names replace existing entries.
    public func copyWith(_ newItems: [CatalogItem], catalogId: String? = nil) -> Catalog {
        var itemsByName: [String: CatalogItem] = [:]
        for item in items {
            itemsByName[item.name] = item
        }
        for item in newItems {
            itemsByName[item.name] = item
        }
        return Catalog(Array(itemsByName.values), catalogId: catalogId ?? self.catalogId)
    }

    /// Creates a copy without the specified items.
    /// Matches items by name before removing them.
    public func copyWithout(_ itemNames: [CatalogItem], catalogId: String? = nil) -> Catalog {
        let namesToRemove = Set(itemNames.map { $0.name })
        let updatedItems = items.filter { !namesToRemove.contains($0.name) }
        return Catalog(updatedItems, catalogId: catalogId ?? self.catalogId)
    }

    /// Builds a SwiftUI view from a catalog item context.
    /// Resolves the component type and invokes its builder.
    public func buildWidget(_ itemContext: CatalogItemContext) -> AnyView {
        guard let widgetData = itemContext.data as? JsonMap,
              let widgetType = widgetData.keys.first else {
            genUiLogger.severe("Item data was not a map or missing widget type")
            return AnyView(EmptyView())
        }

        guard let item = items.first(where: { $0.name == widgetType }) else {
            genUiLogger.severe("Item \(widgetType) was not found in catalog")
            return AnyView(EmptyView())
        }

        genUiLogger.info("Building widget \(item.name) with id \(itemContext.id)")
        let data = widgetData[widgetType] as? JsonMap ?? [:]
        let childContext = CatalogItemContext(
            data: data,
            id: itemContext.id,
            buildChild: { childId, childDataContext in
                itemContext.buildChild(childId, childDataContext ?? itemContext.dataContext)
            },
            dispatchEvent: itemContext.dispatchEvent,
            buildContext: itemContext.buildContext,
            dataContext: itemContext.dataContext,
            getComponent: itemContext.getComponent,
            surfaceId: itemContext.surfaceId
        )
        return item.widgetBuilder(childContext)
    }

    public var definition: Schema {
        let componentProperties = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.dataSchema) })

        return S.object(
            title: "A2UI Catalog Description Schema",
            description: "A schema for a custom Catalog Description including A2UI components and styles.",
            properties: [
                "components": S.object(
                    title: "A2UI Components",
                    description: "A schema that defines a catalog of A2UI components. Each key is a component name, and each value is the JSON schema for that component's properties.",
                    properties: componentProperties
                ),
                "styles": S.object(
                    title: "A2UI Styles",
                    description: "A schema that defines a catalog of A2UI styles. Each key is a style name, and each value is the JSON schema for that style's properties.",
                    properties: [:]
                )
            ],
            required: ["components", "styles"]
        )
    }
}
