//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import GenUI
import Testing
@testable import A2uiSampleAgent

@Suite("A2A service")
struct A2AAgentServiceTests {
    private func makeService() throws -> A2AAgentService {
        var counter = 0
        return A2AAgentService(
            agent: RestaurantAgent(
                data: try RestaurantCatalog(),
                clock: { Date(timeIntervalSince1970: 1_767_225_600) }
            ),
            serviceUrl: "http://localhost:10002/",
            idProvider: {
                counter += 1
                return "id-\(counter)"
            }
        )
    }

    private func streamRequest(
        id: Int = 1,
        contextId: String = "ctx-1",
        parts: JsonArray,
        metadata: JsonMap? = nil,
        method: String = "message/stream"
    ) -> JsonMap {
        var message: JsonMap = [
            "messageId": "m-1",
            "role": "user",
            "contextId": contextId,
            "parts": parts
        ]
        if let metadata {
            message["metadata"] = metadata
        }
        return ["jsonrpc": "2.0", "id": id, "method": method, "params": ["message": message] as JsonMap]
    }

    @Test("The agent card advertises the A2UI extension and its catalogs")
    func agentCard() throws {
        let card = try makeService().agentCard()

        #expect(card["name"] as? String == RestaurantAgent.name)
        #expect(card["url"] as? String == "http://localhost:10002/")

        let capabilities = try #require(Json.map(card["capabilities"]))
        #expect(Json.bool(capabilities["streaming"]) == true)

        let extensions = try #require(Json.array(capabilities["extensions"]))
        let a2ui = try #require(Json.map(extensions.first))
        #expect(a2ui["uri"] as? String == A2uiProtocol.a2aExtensionUri)

        let params = try #require(Json.map(a2ui["params"]))
        #expect(Json.stringArray(params["supportedCatalogIds"]) == [basicCatalogId])
        #expect(Json.bool(params["acceptsInlineCatalogs"]) == false)

        // The card must parse with the client's own decoder.
        let parsed = try A2AAgentCard.fromJson(card)
        #expect(parsed.a2uiCapabilities?.supportedCatalogIds == [basicCatalogId])
    }

    @Test("A streamed request produces a task event and a final message event")
    func streamResponse() throws {
        let service = try makeService()
        let result = service.handle(
            request: streamRequest(parts: [["kind": "text", "text": "chinese in new york"]])
        )

        guard case let .stream(events) = result else {
            Issue.record("Expected a stream result")
            return
        }
        #expect(events.count == 2)

        let task = try #require(Json.map(events[0]["result"]))
        #expect(task["contextId"] as? String == "ctx-1")
        #expect(task["id"] as? String != nil)

        let update = try #require(Json.map(events[1]["result"]))
        #expect(Json.bool(update["end"]) == true)
        #expect(update["taskId"] as? String == task["id"] as? String)

        let message = try #require(Json.map(Json.map(update["status"])?["message"]))
        #expect(message["role"] as? String == "agent")

        let parts = try #require(Json.array(message["parts"]))
        let dataPart = try #require(Json.map(parts.first))
        #expect(Json.map(dataPart["metadata"])?["mimeType"] as? String == A2uiProtocol.mimeType)

        // The payload must be a list of A2UI messages the renderer can decode.
        let payload = try #require(Json.array(dataPart["data"]))
        let decoded = A2uiMessageDecoder.decodeList(payload)
        #expect(decoded.errors.isEmpty)
        #expect(decoded.messages.count == payload.count)
        #expect(decoded.messages.first?.surfaceId == "restaurants-1")
    }

    @Test("The task id is stable across a conversation")
    func taskContinuity() throws {
        let service = try makeService()
        let first = service.handle(request: streamRequest(parts: [["kind": "text", "text": "sushi"]]))
        let second = service.handle(request: streamRequest(id: 2, parts: [["kind": "text", "text": "tacos"]]))

        guard case let .stream(firstEvents) = first, case let .stream(secondEvents) = second else {
            Issue.record("Expected stream results")
            return
        }
        let firstTask = Json.map(firstEvents[0]["result"])?["id"] as? String
        let secondTask = Json.map(secondEvents[0]["result"])?["id"] as? String
        #expect(firstTask == secondTask)

        // A different conversation gets its own task.
        let other = service.handle(
            request: streamRequest(id: 3, contextId: "ctx-2", parts: [["kind": "text", "text": "sushi"]])
        )
        guard case let .stream(otherEvents) = other else {
            Issue.record("Expected a stream result")
            return
        }
        #expect(Json.map(otherEvents[0]["result"])?["id"] as? String != firstTask)
    }

    @Test("message/send returns a single response")
    func singleResponse() throws {
        let service = try makeService()
        let result = service.handle(
            request: streamRequest(parts: [["kind": "text", "text": "sushi"]], method: "message/send")
        )

        guard case let .single(response) = result else {
            Issue.record("Expected a single result")
            return
        }
        #expect(Json.map(response["result"])?["kind"] as? String == "message")
    }

    @Test("Unsupported methods and malformed requests produce JSON-RPC errors")
    func errors() throws {
        let service = try makeService()

        guard case let .failure(unsupported) = service.handle(
            request: streamRequest(parts: [], method: "tasks/cancel")
        ) else {
            Issue.record("Expected a failure result")
            return
        }
        #expect(Json.int(Json.map(unsupported["error"])?["code"]) == -32601)

        guard case let .failure(noMethod) = service.handle(request: ["id": 1]) else {
            Issue.record("Expected a failure result")
            return
        }
        #expect(Json.int(Json.map(noMethod["error"])?["code"]) == -32600)

        guard case let .failure(noMessage) = service.handle(request: ["id": 1, "method": "message/stream"]) else {
            Issue.record("Expected a failure result")
            return
        }
        #expect(Json.int(Json.map(noMessage["error"])?["code"]) == -32602)
    }

    @Test("Renderer messages and metadata are decoded from A2A messages")
    func decoding() throws {
        let message: JsonMap = [
            "contextId": "ctx-9",
            "parts": [
                ["kind": "text", "text": "hello"],
                [
                    "kind": "data",
                    "metadata": ["mimeType": A2uiProtocol.mimeType] as JsonMap,
                    "data": [
                        [
                            "version": "v1.0",
                            "action": [
                                "name": "selectRestaurant",
                                surfaceIdKey: "restaurants-1",
                                "sourceComponentId": "orderButton",
                                "timestamp": "2026-01-01T00:00:00Z",
                                "context": ["restaurantId": "golden-dragon"] as JsonMap
                            ] as JsonMap
                        ],
                        ["version": "v1.0", "unknownMessage": [:] as JsonMap]
                    ]
                ]
            ],
            "metadata": [
                A2uiProtocol.rendererCapabilitiesKey: ["v1.0": ["supportedCatalogIds": [basicCatalogId]] as JsonMap] as JsonMap,
                A2uiProtocol.rendererDataModelKey: [
                    "version": "v1.0",
                    "surfaces": ["order-1": ["order": ["items": ["tea"]] as JsonMap] as JsonMap] as JsonMap
                ] as JsonMap
            ] as JsonMap
        ]

        let request = A2AAgentService.decode(message: message, fallbackContextId: "fallback")

        #expect(request.contextId == "ctx-9")
        #expect(request.text == "hello")
        #expect(request.rendererMessages.count == 1, "unknown messages are skipped")
        #expect(request.capabilities?.supportedCatalogIds == [basicCatalogId])
        #expect(Json.map(request.dataModel?.surfaces["order-1"]?["order"]) != nil)

        guard case let .action(action) = request.rendererMessages[0] else {
            Issue.record("Expected an action")
            return
        }
        #expect(action.name == "selectRestaurant")
        #expect(Json.string(action.context["restaurantId"]) == "golden-dragon")
    }

    @Test("A message without a context id falls back to a generated one")
    func fallbackContext() {
        let request = A2AAgentService.decode(message: ["parts": []], fallbackContextId: "generated")
        #expect(request.contextId == "generated")
        #expect(request.text == nil)
    }

    @Test("A full order flow works end to end over the service")
    func endToEndFlow() throws {
        let service = try makeService()

        func send(_ parts: JsonArray, metadata: JsonMap? = nil) throws -> [A2uiMessage] {
            guard case let .stream(events) = service.handle(
                request: streamRequest(parts: parts, metadata: metadata)
            ) else {
                Issue.record("Expected a stream result")
                return []
            }
            let message = Json.map(Json.map(Json.map(events[1]["result"])?["status"])?["message"])
            let parts = Json.array(message?["parts"]) ?? []
            let dataPart = parts.compactMap { Json.map($0) }.first { Json.array($0["data"]) != nil }
            let payload = Json.array(dataPart?["data"]) ?? []
            let decoded = A2uiMessageDecoder.decodeList(payload)
            #expect(decoded.errors.isEmpty)
            return decoded.messages
        }

        let search = try send([["kind": "text", "text": "chinese in new york"]])
        #expect(search.count == 1)

        let selection = try send([
            [
                "kind": "data",
                "metadata": ["mimeType": A2uiProtocol.mimeType] as JsonMap,
                "data": [
                    [
                        "version": "v1.0",
                        "action": [
                            "name": "selectRestaurant",
                            surfaceIdKey: "restaurants-1",
                            "sourceComponentId": "orderButton",
                            "timestamp": "2026-01-01T00:00:00Z",
                            "context": ["restaurantId": "golden-dragon"] as JsonMap
                        ] as JsonMap
                    ]
                ]
            ]
        ])
        #expect(selection.count == 2, "the previous surface is deleted and the order form created")

        let order = try send(
            [
                [
                    "kind": "data",
                    "metadata": ["mimeType": A2uiProtocol.mimeType] as JsonMap,
                    "data": [
                        [
                            "version": "v1.0",
                            "action": [
                                "name": "placeOrder",
                                surfaceIdKey: "order-2",
                                "sourceComponentId": "placeOrderButton",
                                "timestamp": "2026-01-01T00:00:00Z",
                                "context": [
                                    "restaurantId": "golden-dragon",
                                    "items": ["soup-dumplings"],
                                    "type": ["pickup"]
                                ] as JsonMap
                            ] as JsonMap
                        ]
                    ]
                ]
            ]
        )
        let confirmation = order.compactMap { message -> CreateSurfaceMessage? in
            guard case let .createSurface(payload) = message else { return nil }
            return payload
        }
        #expect(confirmation.first?.surfaceId == "confirmation-3")
    }
}
