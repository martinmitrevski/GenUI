//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

/// Builder for template-driven child lists.
/// Receives data map, component id, and binding path.
public typealias TemplateListWidgetBuilder = (
    JsonMap,
    String,
    String
) -> AnyView

/// Builder for explicit child id lists.
/// Receives child ids, builders, and data context.
public typealias ExplicitListWidgetBuilder = (
    [String],
    @escaping ChildBuilderCallback,
    @escaping GetComponentCallback,
    DataContext
) -> AnyView

/// Helper view for rendering child components.
/// Supports explicit child lists or template bindings.
public struct ComponentChildrenBuilder: View {
    public let childrenData: Any?
    public let dataContext: DataContext
    public let buildChild: ChildBuilderCallback
    public let getComponent: GetComponentCallback
    public let explicitListBuilder: ExplicitListWidgetBuilder
    public let templateListWidgetBuilder: TemplateListWidgetBuilder

    /// Creates a child renderer for list or template bindings.
    /// Provide builders for explicit lists and template-driven lists.
    public init(
        childrenData: Any?,
        dataContext: DataContext,
        buildChild: @escaping ChildBuilderCallback,
        getComponent: @escaping GetComponentCallback,
        explicitListBuilder: @escaping ExplicitListWidgetBuilder,
        templateListWidgetBuilder: @escaping TemplateListWidgetBuilder
    ) {
        self.childrenData = childrenData
        self.dataContext = dataContext
        self.buildChild = buildChild
        self.getComponent = getComponent
        self.explicitListBuilder = explicitListBuilder
        self.templateListWidgetBuilder = templateListWidgetBuilder
    }

    public var body: some View {
        if let explicitList = parseExplicitList(childrenData) {
            explicitListBuilder(explicitList, buildChild, getComponent, dataContext)
        } else if let childrenMap = childrenData as? JsonMap,
                  let template = childrenMap["template"] as? JsonMap,
                  let dataBinding = template["dataBinding"] as? String,
                  let componentId = template["componentId"] as? String {
            let notifier: ValueNotifier<JsonMap?> = dataContext.subscribe(DataPath(dataBinding))
            OptionalValueBuilder(listenable: notifier) { data in
                templateListWidgetBuilder(data, componentId, dataBinding)
            }
            .onAppear {
                genUiLogger.finest("Widget \(componentId) subscribing to \(dataContext.path)")
            }
        } else {
            EmptyView()
        }
    }

    private func parseExplicitList(_ data: Any?) -> [String]? {
        if let list = data as? [String] {
            return list
        }
        if let list = data as? [Any] {
            return list.compactMap { $0 as? String }
        }
        if let map = data as? JsonMap,
           let explicitList = map["explicitList"] as? [Any] {
            return explicitList.compactMap { $0 as? String }
        }
        return nil
    }
}

/// Builds a child view with optional layout weight.
/// Applies `layoutPriority` when a weight is provided.
public func buildWeightedChild(
    componentId: String,
    dataContext: DataContext,
    buildChild: ChildBuilderCallback,
    weight: Int?
) -> AnyView {
    let child = buildChild(componentId, dataContext)
    if let weight {
        return AnyView(child.layoutPriority(Double(weight)))
    }
    return child
}
