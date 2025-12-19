//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import SwiftUI

/// Looks up a component by id within a surface.
/// Returns nil when the component cannot be found.
public typealias GetComponentCallback = (String) -> Component?
/// Builds a SwiftUI view for a child component.
/// Accepts a component id and an optional data context override.
public typealias ChildBuilderCallback = (String, DataContext?) -> AnyView
/// Generates a JSON example string for a catalog item.
/// Used by debug tooling to render sample widgets.
public typealias ExampleBuilderCallback = () -> String
/// Builds the widget view for a catalog item.
/// Receives a rendering context with data and helpers.
public typealias CatalogWidgetBuilder = (CatalogItemContext) -> AnyView

/// Rendering context passed to a catalog widget builder.
/// Includes data, child builders, and event dispatch utilities.
public struct CatalogItemContext {
    public let data: Any
    public let id: String
    public let buildChild: ChildBuilderCallback
    public let dispatchEvent: DispatchEventCallback
    public let buildContext: GenUiBuildContext
    public let dataContext: DataContext
    public let getComponent: GetComponentCallback
    public let surfaceId: String
}

/// Defines a single catalog component.
/// Holds the schema, renderer, and sample data generators.
public struct CatalogItem {
    public let name: String
    public let dataSchema: Schema
    public let widgetBuilder: CatalogWidgetBuilder
    public let exampleData: [ExampleBuilderCallback]

    /// Creates a catalog item definition.
    /// Provide the schema and widget builder for rendering.
    public init(
        name: String,
        dataSchema: Schema,
        widgetBuilder: @escaping CatalogWidgetBuilder,
        exampleData: [ExampleBuilderCallback] = []
    ) {
        self.name = name
        self.dataSchema = dataSchema
        self.widgetBuilder = widgetBuilder
        self.exampleData = exampleData
    }
}
