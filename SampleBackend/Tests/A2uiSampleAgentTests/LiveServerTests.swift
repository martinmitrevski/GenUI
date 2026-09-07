//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import GenUI
import Testing
@testable import A2uiSampleAgent

/// Drives the real HTTP server with the real client.
///
/// The socket layer cannot be exercised by the in-process tests, so this suite
/// runs only when a server is available. Start one and point the tests at it:
///
/// ```bash
/// swift run a2ui-sample-server --port 10002 &
/// A2UI_LIVE_SERVER=http://localhost:10002 swift test
/// ```
@Suite("Live server", .enabled(if: LiveServer.url != nil))
struct LiveServerTests {
    @Test("The agent card is served and advertises A2UI")
    func agentCard() async throws {
        let connector = A2uiAgentConnector(url: try #require(LiveServer.url))
        let card = try await connector.agentCard()

        #expect(card.name == RestaurantAgent.name)
        #expect(card.a2uiCapabilities?.supportedCatalogIds == [basicCatalogId])
    }

    @Test("A prompt streams A2UI messages over server-sent events")
    func streaming() async throws {
        let connector = A2uiAgentConnector(url: try #require(LiveServer.url))
        var messages: [A2uiMessage] = []
        var errors: [Error] = []
        let subscriptions = [
            connector.messages.sink { messages.append($0) },
            connector.errors.sink { errors.append($0) }
        ]

        let text = await connector.send(
            GenerationRequest(
                userMessage: .text("Chinese restaurants in New York"),
                capabilities: RendererCapabilities(supportedCatalogIds: [basicCatalogId])
            )
        )
        subscriptions.forEach { $0.cancel() }

        #expect(errors.isEmpty)
        #expect(messages.count == 1)
        #expect(text?.isEmpty == false)
        #expect(connector.taskId != nil)

        guard case let .createSurface(surface) = try #require(messages.first) else {
            Issue.record("Expected a createSurface message")
            return
        }
        #expect(surface.catalogId == basicCatalogId)
        #expect(surface.components.contains { $0.id == "root" })
    }

    @Test("An action sent as an A2UI data part advances the conversation")
    func actions() async throws {
        let connector = A2uiAgentConnector(url: try #require(LiveServer.url))
        var messages: [A2uiMessage] = []
        let subscription = connector.messages.sink { messages.append($0) }

        await connector.send(GenerationRequest(userMessage: .text("Chinese")))
        messages.removeAll()

        await connector.send(
            GenerationRequest(
                rendererMessages: [
                    .action(
                        RendererAction(
                            name: "selectRestaurant",
                            surfaceId: "restaurants-1",
                            sourceComponentId: "orderButton",
                            context: ["restaurantId": "golden-dragon"]
                        )
                    )
                ],
                capabilities: RendererCapabilities(supportedCatalogIds: [basicCatalogId])
            )
        )
        subscription.cancel()

        #expect(messages.count == 2, "the list surface is deleted and the order form created")
        #expect(messages.contains { message in
            guard case let .createSurface(surface) = message else { return false }
            return surface.sendDataModel
        })
    }
}

/// The address of a running sample server, when the tests should use one.
enum LiveServer {
    /// The URL from `A2UI_LIVE_SERVER`, or `nil` when the variable is unset.
    static var url: URL? {
        guard let value = ProcessInfo.processInfo.environment["A2UI_LIVE_SERVER"] else { return nil }
        return URL(string: value)
    }
}
