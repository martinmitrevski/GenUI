//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Combine
import Foundation
import GenUI

/// Drives the restaurant sample: sends prompts, tracks surfaces and status.
///
/// The view model owns a ``GenUiConversation``, which is the only piece of
/// wiring an app needs: it forwards prompts to the agent, renders the surfaces
/// the agent creates, and sends user actions back automatically.
@MainActor
final class RestaurantSampleViewModel: ObservableObject {
    /// The prompt the user is typing.
    @Published var inputText = ""

    /// The surfaces currently on screen, in creation order.
    @Published var surfaceIds: [String] = []

    /// The agent's most recent text responses.
    @Published var textResponses: [String] = []

    /// The last error, if the agent could not be reached.
    @Published var errorMessage: String?

    /// Whether a request is in flight.
    @Published var isProcessing = false

    /// The name of the connected agent, once its card has been fetched.
    @Published var agentName: String?

    /// The example prompts shown under the input field.
    let examplePrompts = [
        "Top 5 Chinese restaurants in New York",
        "Sushi in San Francisco",
        "Cheap tacos near me"
    ]

    /// The title shown in the header.
    let title = "Restaurant Finder"

    /// The URL of the sample agent.
    let serverUrlString: String

    /// The conversation that connects the agent to the renderer.
    let conversation: GenUiConversation

    private let generator: A2uiContentGenerator
    private var cancellables: Set<AnyCancellable> = []

    /// Creates a view model pointing at a sample server.
    ///
    /// Run the bundled backend with `swift run a2ui-sample-server`. On the iOS
    /// simulator `localhost` reaches the host machine; on a device, pass the
    /// machine's LAN address instead.
    init(serverUrlString: String = "http://localhost:10002") {
        self.serverUrlString = serverUrlString
        let url = URL(string: serverUrlString) ?? URL(string: "http://localhost:10002")!

        generator = A2uiContentGenerator(serverUrl: url)
        conversation = GenUiConversation(
            contentGenerator: generator,
            // The app supports the A2UI basic catalog. `defaultCatalogId`
            // keeps rendering agents that forget to declare a surface catalog.
            processor: A2uiMessageProcessor(
                catalogs: [BasicCatalog.catalog],
                defaultCatalogId: BasicCatalog.catalogId
            )
        )

        conversation.onSurfaceAdded = { [weak self] update in
            self?.trackSurface(update.surfaceId)
        }
        conversation.onSurfaceUpdated = { [weak self] update in
            self?.trackSurface(update.surfaceId)
        }
        conversation.onSurfaceRemoved = { [weak self] update in
            self?.surfaceIds.removeAll { $0 == update.surfaceId }
        }
        conversation.onTextResponse = { [weak self] text in
            self?.textResponses.append(text)
        }
        conversation.onError = { [weak self] error in
            self?.errorMessage = error.localizedDescription
        }

        conversation.isProcessing.$value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isProcessing in
                self?.isProcessing = isProcessing
            }
            .store(in: &cancellables)
    }

    /// Fetches the agent card so the UI can show what it is talking to.
    ///
    /// Set the `A2UI_SAMPLE_PROMPT` environment variable to send a prompt as
    /// soon as the app connects, which is handy for demos and screenshots.
    /// Failures are surfaced as the connection error banner.
    func connect() async {
        do {
            let card = try await generator.connector.agentCard()
            agentName = card.name
            if let capabilities = card.a2uiCapabilities {
                genUiLogger.info("Agent supports catalogs: \(capabilities.supportedCatalogIds)")
            }
        } catch {
            errorMessage = "Could not reach the agent at \(serverUrlString). Is the sample server running?"
            return
        }

        if let prompt = ProcessInfo.processInfo.environment["A2UI_SAMPLE_PROMPT"], !prompt.isEmpty {
            await send(prompt)
        }
    }

    /// Sends the current prompt to the agent.
    /// Clears the input and any previous error first.
    func sendPrompt() async {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        inputText = ""
        await send(prompt)
    }

    /// Sends a specific prompt, used by the example buttons.
    func send(_ prompt: String) async {
        errorMessage = nil
        textResponses.removeAll()
        await conversation.send(text: prompt)
    }

    /// Releases the conversation's resources.
    func dispose() {
        conversation.dispose()
    }

    private func trackSurface(_ surfaceId: String) {
        guard !surfaceId.isEmpty, !surfaceIds.contains(surfaceId) else { return }
        surfaceIds.append(surfaceId)
    }
}
