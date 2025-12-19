//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import Combine

/// Wraps errors emitted by a content generator.
/// Carries the underlying error and an optional stack trace string for reporting.
public struct ContentGeneratorError: Error {
    public let error: Error
    public let stackTrace: String

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(_ error: Error, stackTrace: String = "") {
        self.error = error
        self.stackTrace = stackTrace
    }
}

/// Protocol for components that produce A2UI messages and text responses.
/// Defines streams, processing state, and the request lifecycle used by GenUI.
public protocol ContentGenerator {
    var a2uiMessageStream: AnyPublisher<A2uiMessage, Never> { get }
    var textResponseStream: AnyPublisher<String, Never> { get }
    var errorStream: AnyPublisher<ContentGeneratorError, Never> { get }
    var isProcessing: ValueNotifier<Bool> { get }

    func sendRequest(
        _ message: ChatMessage,
        history: [ChatMessage]?,
        clientCapabilities: A2UiClientCapabilities?
    ) async

    func dispose()
}
