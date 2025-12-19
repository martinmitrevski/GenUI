//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import SwiftUI

/// Callback for resolving components by id.
/// Returns the Component or nil if missing.
public typealias GetComponentCallback = (String) -> Component?
/// Callback to build a child component view.
/// Accepts a component id and optional data context.
public typealias ChildBuilderCallback = (String, DataContext?) -> AnyView
/// Callback that returns JSON example data.
/// Used by debug tooling to render catalog samples.
public typealias ExampleBuilderCallback = () -> String
/// Callback that builds a catalog item view.
/// Receives a CatalogItemContext for rendering.
public typealias CatalogWidgetBuilder = (CatalogItemContext) -> AnyView

/// Context passed to catalog item builders.
/// Provides component data, child builders, and event dispatch hooks.
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

/// Definition for a single catalog component.
/// Includes schema, widget builder, and example data generators.
public struct CatalogItem {
    public let name: String
    public let dataSchema: Schema
    public let widgetBuilder: CatalogWidgetBuilder
    public let exampleData: [ExampleBuilderCallback]

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
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
