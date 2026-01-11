//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import Combine

/// Error wrapper surfaced by a content generator.
/// Carries the underlying error plus an optional stack trace string.
public struct ContentGeneratorError: Error {
    public let error: Error
    public let stackTrace: String

    /// Creates an error wrapper with an optional stack trace.
    /// Use this to forward generator failures through the error stream.
    public init(_ error: Error, stackTrace: String = "") {
        self.error = error
        self.stackTrace = stackTrace
    }
}

/// Produces A2UI messages and text responses for GenUI surfaces.
/// Exposes streams, processing state, and a request lifecycle contract.
public protocol ContentGenerator {
    var a2uiMessageStream: AnyPublisher<A2uiMessage, Never> { get }
    var textResponseStream: AnyPublisher<String, Never> { get }
    var errorStream: AnyPublisher<ContentGeneratorError, Never> { get }
    var isProcessing: ValueNotifier<Bool> { get }

    /// Sends a message to the generator for processing.
    /// Provide optional history and client capabilities to shape the response.
    func sendRequest(
        _ message: Message,
        history: [Message]?,
        clientCapabilities: A2UiClientCapabilities?
    ) async

    /// Stops work and releases any underlying resources.
    /// Call this when the generator is no longer needed.
    func dispose()
}
