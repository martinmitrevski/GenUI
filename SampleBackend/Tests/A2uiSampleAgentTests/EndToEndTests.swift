//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Combine
import Foundation
import GenUI
import Testing
@testable import A2uiSampleAgent

/// Runs the sample agent in process, speaking A2A to the real GenUI client.
///
/// This is the transport layer of the sample server without the socket: the
/// same JSON-RPC payloads the HTTP server would exchange are handed to
/// ``A2AAgentService`` and its events are mapped back into the client's result
/// types. It lets the end-to-end tests exercise the actual protocol encoding on
/// both sides.
private final class InProcessA2AClient: A2AClientProtocol {
    private let service: A2AAgentService
    private var requestId = 0

    init(service: A2AAgentService) {
        self.service = service
    }

    func getAgentCard() async throws -> A2AAgentCard {
        try A2AAgentCard.fromJson(service.agentCard())
    }

    func sendMessageStream(_ payload: A2AMessageSendParams) -> AsyncThrowingStream<A2ASendStreamMessageResponse, Error> {
        requestId += 1
        let request: JsonMap = [
            "jsonrpc": "2.0",
            "id": requestId,
            "method": "message/stream",
            "params": payload.toJson()
        ]
        let result = service.handle(request: request)
        return AsyncThrowingStream { continuation in
            switch result {
            case let .stream(events):
                for event in events {
                    if let response = Self.map(event) {
                        continuation.yield(response)
                    }
                }
            case let .single(response):
                if let mapped = Self.map(response) {
                    continuation.yield(mapped)
                }
            case let .failure(response):
                let error = Json.map(response["error"])
                continuation.yield(
                    A2AJSONRPCErrorResponseSSM(
                        error: A2AError(
                            rpcErrorCode: Json.int(error?["code"]),
                            message: Json.string(error?["message"])
                        )
                    )
                )
            }
            continuation.finish()
        }
    }

    func sendMessage(_ payload: A2AMessageSendParams) async throws {
        requestId += 1
        _ = service.handle(
            request: ["jsonrpc": "2.0", "id": requestId, "method": "message/send", "params": payload.toJson()]
        )
    }

    /// Maps a JSON-RPC response into the client's streamed result types.
    private static func map(_ event: JsonMap) -> A2ASendStreamMessageResponse? {
        guard let result = Json.map(event["result"]) else { return nil }
        let id = Json.int(event["id"])

        if result["messageId"] != nil {
            return A2ASendStreamMessageSuccessResponse(result: A2AMessage.fromJson(result), id: id)
        }
        if result["id"] != nil, result["status"] != nil {
            return A2ASendStreamMessageSuccessResponse(result: A2ATask.fromJson(result), id: id)
        }
        if result["status"] != nil {
            return A2ASendStreamMessageSuccessResponse(result: A2ATaskStatusUpdateEvent.fromJson(result), id: id)
        }
        return nil
    }
}

/// Wires the real client, processor and conversation to the in-process agent.
@MainActor
private final class SampleClient {
    let conversation: GenUiConversation
    let processor: A2uiMessageProcessor
    private(set) var texts: [String] = []
    private(set) var errors: [String] = []
    private var cancellables: Set<AnyCancellable> = []

    init() throws {
        let agent = RestaurantAgent(
            data: try RestaurantCatalog(),
            clock: { Date(timeIntervalSince1970: 1_767_225_600) }
        )
        let service = A2AAgentService(agent: agent, serviceUrl: "http://localhost:10002/")
        let connector = A2uiAgentConnector(
            url: URL(string: "http://localhost:10002")!,
            client: InProcessA2AClient(service: service)
        )
        processor = A2uiMessageProcessor(
            catalogs: [BasicCatalog.catalog],
            services: RendererServices(
                openUrl: { _ in },
                now: { Date(timeIntervalSince1970: 1_767_225_600) },
                locale: Locale(identifier: "en_US"),
                timeZone: TimeZone(identifier: "UTC") ?? .current
            )
        )
        conversation = GenUiConversation(
            contentGenerator: A2uiContentGenerator(
                serverUrl: URL(string: "http://localhost:10002")!,
                connector: connector
            ),
            processor: processor
        )
        conversation.onTextResponse = { [weak self] in self?.texts.append($0) }
        conversation.onError = { [weak self] in self?.errors.append($0.localizedDescription) }
    }

    var surfaceIds: [String] {
        processor.surfaceIds
    }

    func definition(_ surfaceId: String) -> UiDefinition? {
        processor.surfaceViewModel(surfaceId).definition
    }

    /// Performs a component's action exactly as its button would on tap.
    func tap(_ componentId: String, on surfaceId: String) throws {
        let definition = try #require(self.definition(surfaceId))
        let component = try #require(definition.component(componentId))
        let action = try #require(ActionDefinition(component.properties["action"]))
        let renderer = processor.makeRenderer(for: definition)
        renderer.perform(
            action,
            componentId: componentId,
            dataContext: DataContext(processor.dataModel(for: surfaceId), "/")
        )
    }

    /// Performs an action inside a list template scope.
    func tap(_ componentId: String, on surfaceId: String, collection: String, index: Int) throws {
        let definition = try #require(self.definition(surfaceId))
        let component = try #require(definition.component(componentId))
        let action = try #require(ActionDefinition(component.properties["action"]))
        let renderer = processor.makeRenderer(for: definition)
        let scope = DataContext(processor.dataModel(for: surfaceId), "/")
            .collectionScope(path: DataPath(collection), index: index)
        renderer.perform(action, componentId: componentId, dataContext: scope)
    }

    /// Evaluates a component property the way the renderer would.
    func value(_ componentId: String, _ property: String, on surfaceId: String) throws -> Any? {
        let definition = try #require(self.definition(surfaceId))
        let component = try #require(definition.component(componentId))
        let renderer = processor.makeRenderer(for: definition)
        return renderer.evaluator.evaluate(
            component.dynamic(property),
            in: DataContext(processor.dataModel(for: surfaceId), "/")
        )
    }

    /// Waits for the next surface to appear, then returns its id.
    func waitForSurface(after existing: [String]) async -> String? {
        await waitUntil("a new surface") { self.surfaceIds != existing && !self.surfaceIds.isEmpty }
        return surfaceIds.last
    }
}

/// Waits until a condition holds, or fails the test after `timeout` seconds.
@MainActor
private func waitUntil(
    _ description: String,
    timeout: TimeInterval = 3,
    condition: @MainActor () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    Issue.record("Timed out waiting for \(description)", sourceLocation: sourceLocation)
}

@MainActor
@Suite("End to end")
struct EndToEndTests {
    @Test("The whole ordering flow runs over the A2A binding")
    func orderingFlow() async throws {
        let client = try SampleClient()

        // 1. A prompt renders the restaurant list.
        await client.conversation.send(text: "Chinese restaurants in New York")
        let listSurface = try #require(await client.waitForSurface(after: []))
        #expect(listSurface == "restaurants-1")
        #expect(client.definition(listSurface)?.isRenderable == true)
        #expect(client.texts.first?.contains("Pick one") == true)
        #expect(client.errors.isEmpty)

        let restaurants = try #require(
            Json.array(client.processor.dataModel(for: listSurface).value(at: DataPath("/restaurants")))
        )
        #expect(restaurants.count >= 3)

        // 2. Tapping a card's order button opens the order form for that item.
        try client.tap("orderButton", on: listSurface, collection: "/restaurants", index: 0)
        let orderSurface = try #require(await client.waitForSurface(after: [listSurface]))
        #expect(orderSurface == "order-2")
        #expect(client.surfaceIds == [orderSurface], "the list surface was deleted")

        let orderDefinition = try #require(client.definition(orderSurface))
        #expect(orderDefinition.sendDataModel)
        #expect(orderDefinition.component("menuPicker") != nil)

        // 3. The estimate is a function the renderer does not know: it is routed
        //    to the agent and resolves once the response arrives.
        #expect(try client.value("heroEstimate", "text", on: orderSurface) == nil, "pending on first evaluation")
        await waitUntil("the agent function response") {
            (try? client.value("heroEstimate", "text", on: orderSurface)) as? String != nil
        }
        let estimate = try #require(Json.string(try client.value("heroEstimate", "text", on: orderSurface)))
        #expect(estimate.contains("pickup"))

        // 4. The user fills in the form through two-way bindings.
        let model = client.processor.dataModel(for: orderSurface)
        let menu = try #require(Json.array(model.value(at: DataPath("/menu"))) ?? Json.array(orderDefinition.component("menuPicker")?.property("options")))
        let firstOption = try #require(Json.string(Json.map(menu[0])?["value"]))
        model.update(at: DataPath("/order/items"), value: [firstOption])

        // 5. Placing the order renders the confirmation, with the synchronized
        //    data model available to the agent.
        try client.tap("placeOrderButton", on: orderSurface)
        let confirmation = try #require(await client.waitForSurface(after: [orderSurface]))
        #expect(confirmation == "confirmation-3")

        let confirmationModel = client.processor.dataModel(for: confirmation)
        #expect(Json.double(confirmationModel.value(at: DataPath("/confirmation/total"))) ?? 0 > 0)
        #expect(Json.array(confirmationModel.value(at: DataPath("/confirmation/lines")))?.count == 1)
        #expect(client.texts.last?.contains("confirmed") == true)
        #expect(client.errors.isEmpty)

        // 6. The confirmation's formatted values evaluate through the catalog.
        let total = try #require(Json.string(try client.value("totalValue", "text", on: confirmation)))
        #expect(total.hasPrefix("$"))
        let reference = try #require(Json.string(try client.value("confirmationReference", "text", on: confirmation)))
        #expect(reference.hasPrefix("Reference "))
    }

    @Test("Agent capabilities are discovered from the agent card")
    func agentCard() async throws {
        let agent = RestaurantAgent(data: try RestaurantCatalog())
        let service = A2AAgentService(agent: agent, serviceUrl: "http://localhost:10002/")
        let connector = A2uiAgentConnector(
            url: URL(string: "http://localhost:10002")!,
            client: InProcessA2AClient(service: service)
        )

        let card = try await connector.agentCard()
        #expect(card.name == RestaurantAgent.name)
        #expect(card.a2uiCapabilities?.supportedCatalogIds == [basicCatalogId])
    }

    @Test("Server side validation reaches the rendered form")
    func serverSideValidation() async throws {
        let client = try SampleClient()
        await client.conversation.send(text: "Chinese")
        let listSurface = try #require(await client.waitForSurface(after: []))

        try client.tap("orderButton", on: listSurface, collection: "/restaurants", index: 0)
        let orderSurface = try #require(await client.waitForSurface(after: [listSurface]))

        // Placing an order with no dishes: the agent writes the message into the
        // surface's data model instead of creating a new surface.
        try client.tap("placeOrderButton", on: orderSurface)
        await waitUntil("the validation message") {
            Json.string(client.processor.dataModel(for: orderSurface).value(at: DataPath("/order/error")))?.isEmpty == false
        }

        let message = try #require(
            Json.string(client.processor.dataModel(for: orderSurface).value(at: DataPath("/order/error")))
        )
        #expect(message.contains("at least one dish"))
        #expect(client.surfaceIds == [orderSurface])
    }
}
