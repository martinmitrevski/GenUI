//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import SwiftUI

/// Builds SwiftUI views for the components of one surface.
///
/// The renderer walks the adjacency list of a ``UiDefinition`` starting at the
/// `root` component, resolves each component against the surface catalogs, and
/// applies the shared behaviour every component needs: composition validation,
/// accessibility attributes and action dispatch.
public final class SurfaceRenderer {
    /// The maximum nesting depth, which stops cyclic component references.
    public static let defaultMaxDepth = 64

    /// The component tree being rendered.
    public let definition: UiDefinition

    /// The catalogs used to resolve component types.
    public let catalogs: CatalogRegistry

    /// The evaluator used for properties, functions and checks.
    public let evaluator: ExpressionEvaluator

    private let onAction: (RendererAction) -> Void
    private let onError: (RendererError) -> Void
    private let maxDepth: Int

    /// Creates a renderer for one surface definition.
    /// A new renderer is created whenever the definition changes.
    public init(
        definition: UiDefinition,
        catalogs: CatalogRegistry,
        evaluator: ExpressionEvaluator,
        onAction: @escaping (RendererAction) -> Void,
        onError: @escaping (RendererError) -> Void = { _ in },
        maxDepth: Int = SurfaceRenderer.defaultMaxDepth
    ) {
        self.definition = definition
        self.catalogs = catalogs
        self.evaluator = evaluator
        self.onAction = onAction
        self.onError = onError
        self.maxDepth = maxDepth
    }

    /// Looks up a component of the surface by id.
    /// Used by containers to read child metadata such as layout weight.
    public func component(_ id: String) -> Component? {
        definition.component(id)
    }

    /// Builds the view for the surface's `root` component.
    /// Returns an empty view while the root has not arrived yet.
    public func rootView(dataContext: DataContext) -> AnyView {
        guard definition.root != nil else {
            return AnyView(EmptyView())
        }
        return view(
            componentId: A2uiProtocol.rootComponentId,
            dataContext: dataContext,
            parent: nil,
            depth: 0
        )
    }

    /// Builds the view for one component of the surface.
    ///
    /// Unknown ids and unknown component types render as empty views so that a
    /// partially streamed tree still displays, matching the progressive
    /// rendering behaviour required by the specification.
    public func view(
        componentId: String,
        dataContext: DataContext,
        parent: ComponentDefinition?,
        depth: Int
    ) -> AnyView {
        guard depth < maxDepth else {
            let error = RendererError(
                code: RendererError.Code.validationFailed,
                message: "Component nesting exceeded \(maxDepth) levels at '\(componentId)'. "
                    + "The component tree probably contains a cycle.",
                surfaceId: definition.surfaceId,
                path: "/components/\(componentId)"
            )
            genUiLogger.severe(error.message)
            onError(error)
            return AnyView(EmptyView())
        }

        guard let component = definition.component(componentId) else {
            genUiLogger.fine("Component '\(componentId)' is not defined yet on surface '\(definition.surfaceId)'.")
            return AnyView(EmptyView())
        }

        guard let componentDefinition = catalogs.component(component, surfaceCatalogId: definition.catalogId) else {
            let error = RendererError(
                code: RendererError.Code.unknownCatalog,
                message: "Component type '\(component.type)' could not be resolved. "
                    + "Check that its catalog is supported and that the surface declares a catalogId.",
                surfaceId: definition.surfaceId,
                path: "/components/\(componentId)"
            )
            genUiLogger.severe(error.message)
            onError(error)
            return AnyView(EmptyView())
        }

        if let error = CompositionValidator.validate(
            child: componentDefinition,
            childId: componentId,
            parent: parent,
            surfaceId: definition.surfaceId
        ) {
            genUiLogger.severe(error.message)
            onError(error)
            return AnyView(EmptyView())
        }

        let context = ComponentRenderContext(
            component: component,
            definition: componentDefinition,
            surfaceId: definition.surfaceId,
            dataContext: dataContext,
            evaluator: evaluator,
            renderer: self,
            depth: depth
        )

        if let hidden = evaluator.bool(component.accessibility?.hidden ?? .missing, in: dataContext), hidden {
            return AnyView(componentDefinition.builder(context).accessibilityHidden(true))
        }

        return AnyView(
            componentDefinition.builder(context)
                .modifier(AccessibilityAttributesModifier(
                    attributes: component.accessibility,
                    evaluator: evaluator,
                    dataContext: dataContext
                ))
        )
    }

    /// Performs an action triggered by a component.
    ///
    /// Event actions are resolved against the data model and handed to the
    /// host, while function actions are evaluated locally or routed to the
    /// agent by the evaluator.
    public func perform(_ action: ActionDefinition, componentId: String, dataContext: DataContext) {
        switch action {
        case let .event(event):
            var context: JsonMap = [:]
            for (key, value) in event.context {
                context[key] = evaluator.evaluate(value, in: dataContext) ?? NSNull()
            }
            let rendererAction = RendererAction(
                name: event.name,
                userMessage: evaluator.string(event.userMessage, in: dataContext),
                surfaceId: definition.surfaceId,
                sourceComponentId: componentId,
                timestamp: evaluator.services.now(),
                context: context
            )
            genUiLogger.info("Dispatching action '\(event.name)' from '\(componentId)'.")
            onAction(rendererAction)
        case let .functionCall(call):
            genUiLogger.info("Invoking function '\(call.name)' from '\(componentId)'.")
            _ = evaluator.invoke(call, in: dataContext)
        }
    }

    /// Reports a renderer-side error for this surface.
    /// Components use this for failures they detect while rendering.
    public func report(_ error: RendererError) {
        onError(error)
    }
}

/// Applies A2UI accessibility attributes to a rendered component.
private struct AccessibilityAttributesModifier: ViewModifier {
    let attributes: AccessibilityAttributes?
    let evaluator: ExpressionEvaluator
    let dataContext: DataContext

    func body(content: Content) -> some View {
        guard let attributes else { return AnyView(content) }

        var view = AnyView(content)
        if let label = evaluator.string(attributes.label, in: dataContext), !label.isEmpty {
            view = AnyView(view.accessibilityLabel(Text(label)))
        }
        if let hint = evaluator.string(attributes.description, in: dataContext), !hint.isEmpty {
            view = AnyView(view.accessibilityHint(Text(hint)))
        }
        switch attributes.live {
        case .off:
            break
        case .polite, .assertive:
            view = AnyView(view.accessibilityAddTraits(.updatesFrequently))
        }
        return view
    }
}
