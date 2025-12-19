//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import Combine

public final class A2uiContentGenerator: ContentGenerator {
    public let connector: A2uiAgentConnector

    private let textResponseController = PassthroughSubject<String, Never>()
    private let errorResponseController = PassthroughSubject<ContentGeneratorError, Never>()
    private let isProcessingNotifier = ValueNotifier<Bool>(false)
    private var cancellables: Set<AnyCancellable> = []

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(serverUrl: URL, connector: A2uiAgentConnector? = nil) {
        self.connector = connector ?? A2uiAgentConnector(url: serverUrl)

        self.connector.errorStream
            .sink { [weak self] error in
                self?.errorResponseController.send(ContentGeneratorError(error))
            }
            .store(in: &cancellables)
    }

    public var a2uiMessageStream: AnyPublisher<A2uiMessage, Never> {
        connector.stream
    }

    public var textResponseStream: AnyPublisher<String, Never> {
        textResponseController.eraseToAnyPublisher()
    }

    public var errorStream: AnyPublisher<ContentGeneratorError, Never> {
        errorResponseController.eraseToAnyPublisher()
    }

    public var isProcessing: ValueNotifier<Bool> {
        isProcessingNotifier
    }

    /// Releases resources and closes streams.
    /// Call when the instance is no longer needed.
    public func dispose() {
        textResponseController.send(completion: .finished)
        connector.dispose()
        cancellables.removeAll()
    }

    /// Sends a user message to the content generator.
    /// Optionally passes history and client capabilities.
    public func sendRequest(
        _ message: ChatMessage,
        history: [ChatMessage]?,
        clientCapabilities: A2UiClientCapabilities?
    ) async {
        isProcessingNotifier.value = true
        defer { isProcessingNotifier.value = false }

        if let history, !history.isEmpty {
            genUiLogger.warning("A2uiContentGenerator is stateful and ignores history.")
        }

        let responseText = await connector.connectAndSend(
            message,
            clientCapabilities: clientCapabilities
        )

        if let responseText, !responseText.isEmpty {
            textResponseController.send(responseText)
        }
    }
}
