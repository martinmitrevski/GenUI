//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import Combine

public final class GenUiConversation {
    public let contentGenerator: ContentGenerator
    public let a2uiMessageProcessor: A2uiMessageProcessor

    public var onSurfaceAdded: ((SurfaceAdded) -> Void)?
    public var onSurfaceUpdated: ((SurfaceUpdated) -> Void)?
    public var onSurfaceDeleted: ((SurfaceRemoved) -> Void)?
    public var onTextResponse: ((String) -> Void)?
    public var onError: ((ContentGeneratorError) -> Void)?

    private var cancellables: Set<AnyCancellable> = []
    private let conversationNotifier = ValueNotifier<[ChatMessage]>([])

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(
        contentGenerator: ContentGenerator,
        a2uiMessageProcessor: A2uiMessageProcessor,
        onSurfaceAdded: ((SurfaceAdded) -> Void)? = nil,
        onSurfaceUpdated: ((SurfaceUpdated) -> Void)? = nil,
        onSurfaceDeleted: ((SurfaceRemoved) -> Void)? = nil,
        onTextResponse: ((String) -> Void)? = nil,
        onError: ((ContentGeneratorError) -> Void)? = nil
    ) {
        self.contentGenerator = contentGenerator
        self.a2uiMessageProcessor = a2uiMessageProcessor
        self.onSurfaceAdded = onSurfaceAdded
        self.onSurfaceUpdated = onSurfaceUpdated
        self.onSurfaceDeleted = onSurfaceDeleted
        self.onTextResponse = onTextResponse
        self.onError = onError

        contentGenerator.a2uiMessageStream
            .sink { [weak self] message in
                self?.a2uiMessageProcessor.handleMessage(message)
            }
            .store(in: &cancellables)

        a2uiMessageProcessor.onSubmit
            .sink { [weak self] message in
                Task { await self?.sendRequest(message) }
            }
            .store(in: &cancellables)

        a2uiMessageProcessor.surfaceUpdates
            .sink { [weak self] update in
                self?.handleSurfaceUpdate(update)
            }
            .store(in: &cancellables)

        contentGenerator.textResponseStream
            .sink { [weak self] text in
                self?.handleTextResponse(text)
            }
            .store(in: &cancellables)

        contentGenerator.errorStream
            .sink { [weak self] error in
                self?.handleError(error)
            }
            .store(in: &cancellables)
    }

    /// Releases resources and closes streams.
    /// Call when the instance is no longer needed.
    public func dispose() {
        cancellables.removeAll()
        contentGenerator.dispose()
        a2uiMessageProcessor.dispose()
    }

    public var host: GenUiHost {
        a2uiMessageProcessor
    }

    public var conversation: ValueNotifier<[ChatMessage]> {
        conversationNotifier
    }

    public var isProcessing: ValueNotifier<Bool> {
        contentGenerator.isProcessing
    }

    /// Returns a notifier for the given surface.
    /// Convenience access through the conversation facade.
    public func surface(_ surfaceId: String) -> ValueNotifier<UiDefinition?> {
        a2uiMessageProcessor.getSurfaceNotifier(surfaceId)
    }

    /// Sends a user message to the content generator.
    /// Optionally passes history and client capabilities.
    public func sendRequest(_ message: ChatMessage) async {
        let history = conversationNotifier.value
        if !(message is UserUiInteractionMessage) {
            conversationNotifier.value = history + [message]
        }

        let supportedCatalogIds = a2uiMessageProcessor.catalogs
            .compactMap { $0.catalogId }
        let clientCapabilities = A2UiClientCapabilities(supportedCatalogIds: supportedCatalogIds)

        await contentGenerator.sendRequest(
            message,
            history: history,
            clientCapabilities: clientCapabilities
        )
    }

    private func handleSurfaceUpdate(_ update: GenUiUpdate) {
        switch update {
        case let added as SurfaceAdded:
            conversationNotifier.value = conversationNotifier.value + [
                AiUiMessage(definition: added.definition, surfaceId: added.surfaceId)
            ]
            onSurfaceAdded?(added)
        case let updated as SurfaceUpdated:
            var newConversation = conversationNotifier.value
            if let index = newConversation.lastIndex(where: { message in
                if let uiMessage = message as? AiUiMessage {
                    return uiMessage.surfaceId == updated.surfaceId
                }
                return false
            }) {
                newConversation[index] = AiUiMessage(definition: updated.definition, surfaceId: updated.surfaceId)
            } else {
                newConversation.append(AiUiMessage(definition: updated.definition, surfaceId: updated.surfaceId))
            }
            conversationNotifier.value = newConversation
            onSurfaceUpdated?(updated)
        case let removed as SurfaceRemoved:
            var newConversation = conversationNotifier.value
            newConversation.removeAll { message in
                if let uiMessage = message as? AiUiMessage {
                    return uiMessage.surfaceId == removed.surfaceId
                }
                return false
            }
            conversationNotifier.value = newConversation
            onSurfaceDeleted?(removed)
        default:
            break
        }
    }

    private func handleTextResponse(_ text: String) {
        conversationNotifier.value = conversationNotifier.value + [AiTextMessage.text(text)]
        onTextResponse?(text)
    }

    private func handleError(_ error: ContentGeneratorError) {
        let errorResponse = AiTextMessage.text("An error occurred: \(error.error)")
        conversationNotifier.value = conversationNotifier.value + [errorResponse]
        onError?(error)
    }
}
