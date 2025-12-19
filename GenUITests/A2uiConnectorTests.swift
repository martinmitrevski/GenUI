//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import Combine
import Testing
@testable import GenUI

final class MockA2AClient: A2AClientProtocol {
    func getAgentCard() async throws -> A2AAgentCard {
        A2AAgentCard(
            name: "Agent",
            description: "Description",
            version: "1.0",
            url: "https://example.com",
            capabilities: A2AAgentCapabilities(streaming: true)
        )
    }

    func sendMessageStream(_ payload: A2AMessageSendParams) -> AsyncThrowingStream<A2ASendStreamMessageResponse, Error> {
        AsyncThrowingStream { continuation in
            let dataPart = A2ADataPart(data: [
                "surfaceUpdate": [
                    surfaceIdKey: "surface",
                    "components": []
                ]
            ])
            let textPart = A2ATextPart(text: "Hello")
            let message = A2AMessage(parts: [dataPart, textPart])
            let response = A2ASendStreamMessageSuccessResponse(result: message)
            continuation.yield(response)
            continuation.finish()
        }
    }

    func sendMessage(_ payload: A2AMessageSendParams) async throws {
    }
}

struct A2uiConnectorTests {
    @Test func agentCardFetches() async throws {
        let connector = A2uiAgentConnector(url: URL(string: "https://example.com")!, client: MockA2AClient())
        let card = try await connector.getAgentCard()

        #expect(card.name == "Agent")
    }

    @Test func connectAndSendEmitsMessages() async {
        let connector = A2uiAgentConnector(url: URL(string: "https://example.com")!, client: MockA2AClient())
        var received: [A2uiMessage] = []
        let cancellable = connector.stream.sink { received.append($0) }

        let text = await connector.connectAndSend(UserMessage.text("Hi"))

        #expect(text == "Hello")
        #expect(received.count == 1)
        _ = cancellable
    }
}

struct A2uiContentGeneratorTests {
    @Test func sendRequestReturnsText() async {
        let connector = A2uiAgentConnector(url: URL(string: "https://example.com")!, client: MockA2AClient())
        let generator = A2uiContentGenerator(serverUrl: URL(string: "https://example.com")!, connector: connector)

        var received: [String] = []
        let cancellable = generator.textResponseStream.sink { received.append($0) }

        await generator.sendRequest(UserMessage.text("Hi"), history: nil, clientCapabilities: nil)

        #expect(received.contains("Hello"))
        _ = cancellable
    }
}

struct A2AClientModelTests {
    @Test func messageSerializes() {
        let message = A2AMessage(parts: [A2ATextPart(text: "Hi")])
        let json = message.toJson()

        #expect(json["role"] as? String == "user")
        #expect(json["parts"] != nil)
    }
}
