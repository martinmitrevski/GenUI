//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Combine
import Foundation
import GenUI

@MainActor
final class RestaurantSampleViewModel: ObservableObject {
    @Published var inputText = ""
    @Published var surfaceIds: [String] = []
    @Published var textResponses: [String] = []
    @Published var errorMessage: String?
    @Published var loadingText: String
    @Published var isProcessing = false

    let title = "Restaurant Finder"
    let placeholder = "Top 5 Chinese restaurants in New York."
    let serverUrlString: String

    private let loadingTexts = [
        "Finding the best spots for you...",
        "Checking reviews...",
        "Looking for open tables...",
        "Almost there..."
    ]
    private var loadingIndex = 0
    private var loadingTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    let conversation: GenUiConversation
    private let messageProcessor: A2uiMessageProcessor
    let processingNotifier: ValueNotifier<Bool>

    init(serverUrlString: String = "http://localhost:10002") {
        self.serverUrlString = serverUrlString
        self.loadingText = "Finding the best spots for you..."

        let catalog = CoreCatalogItems.asCatalog()
        let processor = A2uiMessageProcessor(catalogs: [catalog])
        self.messageProcessor = processor
        let baseUrl = URL(string: serverUrlString) ?? URL(string: "http://localhost:10002")!
        let generator = A2uiContentGenerator(serverUrl: baseUrl)
        self.conversation = GenUiConversation(
            contentGenerator: generator,
            a2uiMessageProcessor: processor,
            handleSubmitEvents: false
        )
        self.processingNotifier = conversation.isProcessing

        conversation.onSurfaceAdded = { [weak self] update in
            self?.upsertSurfaceId(update.surfaceId)
        }
        conversation.onSurfaceUpdated = { [weak self] update in
            self?.upsertSurfaceId(update.surfaceId)
        }
        conversation.onSurfaceDeleted = { [weak self] update in
            self?.surfaceIds.removeAll { $0 == update.surfaceId }
        }
        conversation.onTextResponse = { [weak self] text in
            self?.textResponses.append(text)
        }
        conversation.onError = { [weak self] error in
            self?.errorMessage = error.error.localizedDescription
        }

        messageProcessor.onSubmit
            .sink { [weak self] message in
                self?.conversation.clearSurfaces()
                Task { await self?.conversation.sendRequest(message) }
            }
            .store(in: &cancellables)


        processingNotifier.$value
            .receive(on: RunLoop.main)
            .sink { [weak self] isProcessing in
                self?.isProcessing = isProcessing
                self?.updateLoadingTimer(active: isProcessing)
            }
            .store(in: &cancellables)
    }

    func sendPrompt() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        conversation.clearSurfaces()
        inputText = ""
        await conversation.sendRequest(UserMessage.text(trimmed))
    }

    func dispose() {
        loadingTimer?.invalidate()
        loadingTimer = nil
        conversation.dispose()
    }

    private func upsertSurfaceId(_ surfaceId: String) {
        guard !surfaceId.isEmpty else { return }
        if !surfaceIds.contains(surfaceId) {
            surfaceIds.append(surfaceId)
        }
    }

    private func updateLoadingTimer(active: Bool) {
        if active {
            if loadingTimer != nil { return }
            loadingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.loadingIndex = (self.loadingIndex + 1) % self.loadingTexts.count
                    self.loadingText = self.loadingTexts[self.loadingIndex]
                }
            }
        } else {
            loadingTimer?.invalidate()
            loadingTimer = nil
            loadingIndex = 0
            loadingText = loadingTexts[loadingIndex]
        }
    }
}
