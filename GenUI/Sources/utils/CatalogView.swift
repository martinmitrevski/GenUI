//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI
import Combine

/// SwiftUI view that renders catalog examples.
/// Useful for development and visual validation.
public struct DebugCatalogView: View {
    @StateObject private var viewModel: DebugCatalogViewModel
    public let itemHeight: CGFloat?

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(
        catalog: Catalog,
        onSubmit: ((UserUiInteractionMessage) -> Void)? = nil,
        itemHeight: CGFloat? = nil
    ) {
        self._viewModel = StateObject(wrappedValue: DebugCatalogViewModel(catalog: catalog, onSubmit: onSubmit))
        self.itemHeight = itemHeight
    }

    public var body: some View {
        List(viewModel.surfaceIds, id: \.self) { surfaceId in
            VStack(alignment: .center, spacing: 8) {
                Text(surfaceId)
                    .font(.headline)
                GenUiSurface(host: viewModel.messageProcessor, surfaceId: surfaceId)
                    .frame(height: itemHeight)
            }
            .padding(8)
        }
    }
}

final class DebugCatalogViewModel: ObservableObject {
    let messageProcessor: A2uiMessageProcessor
    @Published var surfaceIds: [String] = []

    private var cancellable: AnyCancellable?

    init(catalog: Catalog, onSubmit: ((UserUiInteractionMessage) -> Void)?) {
        self.messageProcessor = A2uiMessageProcessor(catalogs: [catalog])

        if let onSubmit {
            cancellable = messageProcessor.onSubmit.sink(receiveValue: onSubmit)
        }

        for item in catalog.items {
            for index in item.exampleData.indices {
                let exampleBuilder = item.exampleData[index]
                let indexPart = item.exampleData.count > 1 ? "-\(index)" : ""
                let surfaceId = "\(item.name)\(indexPart)"

                let exampleJsonString = exampleBuilder()
                guard let data = exampleJsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data, options: []),
                      let list = json as? [Any] else {
                    continue
                }

                let components = list.compactMap { entry -> Component? in
                    guard let map = entry as? JsonMap else { return nil }
                    return Component.fromJson(map)
                }

                guard let rootComponent = components.first(where: { $0.id == "root" }) else {
                    continue
                }

                messageProcessor.handleMessage(SurfaceUpdate(surfaceId: surfaceId, components: components))
                messageProcessor.handleMessage(BeginRendering(surfaceId: surfaceId, root: rootComponent.id))
                surfaceIds.append(surfaceId)
            }
        }
    }

    deinit {
        cancellable?.cancel()
        messageProcessor.dispose()
    }
}
