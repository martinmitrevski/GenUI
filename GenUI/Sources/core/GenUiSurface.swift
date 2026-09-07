//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

/// Renders one agent-driven surface.
///
/// The view binds to the host's state for `surfaceId` and rebuilds whenever the
/// surface's components or data change. Before the agent creates the surface,
/// or while its `root` component has not arrived yet, the placeholder is shown.
///
/// ```swift
/// GenUiSurface(host: conversation.host, surfaceId: "main") {
///     AnyView(ProgressView())
/// }
/// ```
public struct GenUiSurface: View {
    private let host: GenUiHost
    private let placeholder: (() -> AnyView)?

    /// The surface being rendered.
    public let surfaceId: String

    @ObservedObject private var viewModel: SurfaceViewModel

    /// Creates a surface view bound to a host.
    /// Provide a placeholder to show while the surface is empty.
    public init(host: GenUiHost, surfaceId: String, placeholder: (() -> AnyView)? = nil) {
        self.host = host
        self.surfaceId = surfaceId
        self.placeholder = placeholder
        self.viewModel = host.surfaceViewModel(surfaceId)
    }

    public var body: some View {
        // `revision` is read so SwiftUI re-evaluates bindings and function
        // calls whenever the surface's data model changes.
        let _ = viewModel.revision

        if let definition = viewModel.definition, definition.isRenderable {
            host.makeRenderer(for: definition)
                .rootView(dataContext: DataContext(viewModel.dataModel, "/"))
        } else {
            placeholder?() ?? AnyView(EmptyView())
        }
    }
}
