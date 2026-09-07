//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import GenUI
import Testing
@testable import A2uiSampleAgent

/// A small, fixed data set so assertions do not depend on the bundled JSON.
private enum TestData {
    static let goldenDragon = Restaurant(
        id: "golden-dragon",
        name: "Golden Dragon",
        cuisine: "Chinese • Dim Sum",
        city: "New York",
        neighborhood: "Chinatown",
        rating: 4.7,
        reviewCount: 1284,
        priceRange: "$$",
        distanceMiles: 0.6,
        prepMinutes: 25,
        imageUrl: "https://example.com/golden.jpg",
        menu: [
            MenuItem(
                id: "dumplings",
                name: "Soup dumplings",
                description: "Eight pieces",
                price: 12.5,
                imageUrl: "https://example.com/dumplings.jpg"
            ),
            MenuItem(id: "tea", name: "Jasmine tea", description: "Pot", price: 4.0)
        ]
    )

    static let kaiseki = Restaurant(
        id: "kaiseki-nine",
        name: "Kaiseki Nine",
        cuisine: "Japanese • Sushi",
        city: "San Francisco",
        neighborhood: "Hayes Valley",
        rating: 4.9,
        reviewCount: 611,
        priceRange: "$$$$",
        distanceMiles: 0.9,
        prepMinutes: 45,
        imageUrl: "https://example.com/kaiseki.jpg",
        menu: [MenuItem(id: "omakase", name: "Omakase", description: "Nine courses", price: 145)]
    )

    static let catalog = RestaurantCatalog(restaurants: [goldenDragon, kaiseki])
    static let referenceDate = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z

    static func agent() -> RestaurantAgent {
        RestaurantAgent(data: catalog, clock: { referenceDate })
    }
}

/// Reads the first `createSurface` payload out of an agent response.
private func createSurface(in response: AgentResponse) throws -> CreateSurfaceMessage {
    for message in response.messages {
        if case let .createSurface(payload) = message { return payload }
    }
    throw TestFailure.missingMessage("createSurface")
}

private enum TestFailure: Error {
    case missingMessage(String)
}

/// Builds an action as the renderer would send it.
private func action(
    _ name: String,
    surfaceId: String = "order-2",
    context: JsonMap = [:]
) -> RendererMessage {
    .action(
        RendererAction(
            name: name,
            surfaceId: surfaceId,
            sourceComponentId: "button",
            timestamp: TestData.referenceDate,
            context: context
        )
    )
}

@Suite("Restaurant data")
struct RestaurantDataTests {
    @Test("Queries match on name, cuisine, city and neighborhood")
    func matching() {
        #expect(TestData.goldenDragon.matches(query: "chinese"))
        #expect(TestData.goldenDragon.matches(query: "dim sum in new york"))
        #expect(TestData.goldenDragon.matches(query: "chinatown"))
        #expect(!TestData.goldenDragon.matches(query: "sushi"))
    }

    @Test("Stop words and short tokens are ignored")
    func searchWords() {
        #expect(Restaurant.searchWords(in: "Top 5 best restaurants in New York") == ["new", "york"])
        #expect(Restaurant.searchWords(in: "find me food").isEmpty)
        #expect(TestData.goldenDragon.matches(query: "find me food"), "an empty query matches everything")
    }

    @Test("Search sorts by rating and falls back to the whole list")
    func search() {
        #expect(TestData.catalog.search("sushi").map(\.id) == ["kaiseki-nine"])
        #expect(TestData.catalog.search("nothing here").map(\.id) == ["kaiseki-nine", "golden-dragon"])
        #expect(TestData.catalog.search("chinese", limit: 1).count == 1)
        #expect(TestData.catalog.restaurant(id: "golden-dragon") != nil)
        #expect(TestData.catalog.restaurant(id: "nope") == nil)
    }

    @Test("The bundled data set loads and is self-consistent")
    func bundledData() throws {
        let catalog = try RestaurantCatalog()

        #expect(catalog.restaurants.count >= 5)
        for restaurant in catalog.restaurants {
            #expect(!restaurant.menu.isEmpty, "\(restaurant.name) has no menu")
            #expect(restaurant.rating > 0 && restaurant.rating <= 5)
            #expect(restaurant.imageUrl.hasPrefix("https://"))
            #expect(Set(restaurant.menu.map(\.id)).count == restaurant.menu.count, "duplicate menu ids")
            for item in restaurant.menu {
                #expect(
                    item.imageUrl?.hasPrefix("https://") == true,
                    "\(restaurant.name): \(item.name) has no photo"
                )
            }
        }
        #expect(Set(catalog.restaurants.map(\.id)).count == catalog.restaurants.count, "duplicate restaurant ids")
    }
}

@Suite("Restaurant agent")
struct RestaurantAgentTests {
    @Test("A prompt renders a list of restaurants bound to the data model")
    func search() throws {
        let response = TestData.agent().respond(to: AgentRequest(contextId: "ctx", text: "chinese in new york"))
        let surface = try createSurface(in: response)

        #expect(surface.surfaceId == "restaurants-1")
        #expect(surface.catalogId == basicCatalogId)
        #expect(surface.components.contains { $0.id == "root" })
        #expect(response.text?.contains("Golden Dragon") == true)

        let restaurants = try #require(Json.array(surface.dataModel?["restaurants"]))
        #expect(restaurants.count == 1)
        #expect(Json.string(Json.map(restaurants[0])?["name"]) == "Golden Dragon")

        // The list repeats one template component over the bound collection.
        let list = try #require(surface.components.first { $0.id == "restaurantList" })
        #expect(
            ChildList(list.properties["children"])
                == .template(componentId: "restaurantCard", path: DataPath("/restaurants"))
        )
    }

    @Test("Selecting a restaurant opens an order form and replaces the list")
    func selectRestaurant() throws {
        let agent = TestData.agent()
        _ = agent.respond(to: AgentRequest(contextId: "ctx", text: "chinese"))
        let response = agent.respond(
            to: AgentRequest(
                contextId: "ctx",
                rendererMessages: [action("selectRestaurant", surfaceId: "restaurants-1", context: ["restaurantId": "golden-dragon"])]
            )
        )

        // The previous surface is deleted, because surface ids are never reused.
        guard case let .deleteSurface(deletion) = response.messages.first else {
            Issue.record("Expected the previous surface to be deleted")
            return
        }
        #expect(deletion.surfaceId == "restaurants-1")

        let surface = try createSurface(in: response)
        #expect(surface.surfaceId == "order-2")
        #expect(surface.sendDataModel, "the order form syncs its data model back to the agent")

        let order = try #require(Json.map(surface.dataModel?["order"]))
        #expect(Json.stringArray(order["items"])?.isEmpty == true)
        #expect(Json.stringArray(order["type"]) == ["pickup"])
        #expect(Json.string(order["when"]) == "2026-01-01T00:25:00Z", "defaults to the kitchen's prep time")

        let picker = try #require(surface.components.first { $0.id == "menuPicker" })
        #expect(Json.array(picker.properties["options"])?.count == 2)
        #expect(picker.checks.count == 1)

        let estimate = try #require(surface.components.first { $0.id == "heroEstimate" })
        guard case let .function(call) = estimate.dynamic("text") else {
            Issue.record("The estimate should be an agent-routed function call")
            return
        }
        #expect(call.name == "deliveryEstimate")
    }

    @Test("An unknown restaurant is reported instead of rendering")
    func unknownRestaurant() {
        let response = TestData.agent().respond(
            to: AgentRequest(
                contextId: "ctx",
                rendererMessages: [action("selectRestaurant", context: ["restaurantId": "nope"])]
            )
        )

        #expect(response.messages.isEmpty)
        #expect(response.text?.contains("could not find") == true)
    }

    @Test("Placing an order computes the totals and confirms")
    func placeOrder() throws {
        let agent = TestData.agent()
        _ = agent.respond(to: AgentRequest(contextId: "ctx", text: "chinese"))
        _ = agent.respond(
            to: AgentRequest(
                contextId: "ctx",
                rendererMessages: [action("selectRestaurant", context: ["restaurantId": "golden-dragon"])]
            )
        )

        let response = agent.respond(
            to: AgentRequest(
                contextId: "ctx",
                rendererMessages: [
                    action(
                        "placeOrder",
                        context: [
                            "restaurantId": "golden-dragon",
                            "items": ["dumplings", "tea"],
                            "type": ["pickup"],
                            "when": "2026-01-01T18:30:00Z",
                            "address": "",
                            "notes": "Extra chili",
                            "utensils": true
                        ]
                    )
                ]
            )
        )

        let surface = try createSurface(in: response)
        #expect(surface.surfaceId == "confirmation-3")

        let confirmation = try #require(Json.map(surface.dataModel?["confirmation"]))
        #expect(Json.double(confirmation["subtotal"]) == 16.5)
        #expect(Json.double(confirmation["deliveryFee"]) == 0)
        #expect(Json.double(confirmation["tax"]) == 1.44)
        #expect(Json.double(confirmation["total"]) == 17.94)
        let lines = try #require(Json.array(confirmation["lines"]))
        #expect(lines.count == 2)
        #expect(Json.string(Json.map(lines[0])?["image"]) == "https://example.com/dumplings.jpg")
        #expect(Json.string(Json.map(lines[1])?["image"]) == "", "a dish without a photo sends an empty url")
        #expect(Json.string(confirmation["headline"]) == "Order confirmed")

        // Each line renders a thumbnail bound to the item's own photo.
        let photo = try #require(surface.components.first { $0.id == "lineItemPhoto" })
        #expect(photo.type == "Image")
        #expect(photo.dynamic("url") == .binding(DataPath("image")))
        let lineRow = try #require(surface.components.first { $0.id == "lineItemRow" })
        #expect(ChildList(lineRow.properties["children"]).staticIds.first == "lineItemPhoto")
        #expect(Json.string(confirmation["fulfilment"])?.contains("Pickup") == true)
        #expect(response.text?.contains("confirmed") == true)
    }

    @Test("Delivery adds the fee and requires an address")
    func deliveryValidation() throws {
        let agent = TestData.agent()
        _ = agent.respond(
            to: AgentRequest(
                contextId: "ctx",
                rendererMessages: [action("selectRestaurant", context: ["restaurantId": "golden-dragon"])]
            )
        )

        let rejected = agent.respond(
            to: AgentRequest(
                contextId: "ctx",
                rendererMessages: [
                    action(
                        "placeOrder",
                        surfaceId: "order-1",
                        context: ["restaurantId": "golden-dragon", "items": ["tea"], "type": ["delivery"], "address": ""]
                    )
                ]
            )
        )

        // Server-side validation writes the message into the form's data model.
        guard case let .updateDataModel(update) = rejected.messages.first else {
            Issue.record("Expected a data model update carrying the error")
            return
        }
        #expect(update.surfaceId == "order-1")
        #expect(update.path.description == "/order/error")
        #expect(Json.string(update.value)?.contains("delivery address") == true)

        let accepted = agent.respond(
            to: AgentRequest(
                contextId: "ctx",
                rendererMessages: [
                    action(
                        "placeOrder",
                        surfaceId: "order-1",
                        context: [
                            "restaurantId": "golden-dragon",
                            "items": ["tea"],
                            "type": ["delivery"],
                            "address": "12 Mott St, New York"
                        ]
                    )
                ]
            )
        )
        let confirmation = try #require(Json.map(try createSurface(in: accepted).dataModel?["confirmation"]))
        #expect(Json.double(confirmation["deliveryFee"]) == 4.99)
        #expect(Json.string(confirmation["headline"]) == "Order on the way")
    }

    @Test("An order with no dishes is rejected")
    func emptyOrder() {
        let agent = TestData.agent()
        let response = agent.respond(
            to: AgentRequest(
                contextId: "ctx",
                rendererMessages: [
                    action("placeOrder", context: ["restaurantId": "golden-dragon", "items": [String]()])
                ]
            )
        )

        #expect(response.text?.contains("at least one dish") == true)
    }

    @Test("The synchronized data model is used when the action context is empty")
    func dataModelFallback() throws {
        let agent = TestData.agent()
        _ = agent.respond(
            to: AgentRequest(
                contextId: "ctx",
                rendererMessages: [action("selectRestaurant", context: ["restaurantId": "golden-dragon"])]
            )
        )

        let response = agent.respond(
            to: AgentRequest(
                contextId: "ctx",
                rendererMessages: [action("placeOrder", surfaceId: "order-1")],
                dataModel: RendererDataModel(
                    surfaces: [
                        "order-1": [
                            "restaurant": ["id": "golden-dragon"] as JsonMap,
                            "order": ["items": ["tea"], "type": ["pickup"]] as JsonMap
                        ]
                    ]
                )
            )
        )

        let confirmation = try #require(Json.map(try createSurface(in: response).dataModel?["confirmation"]))
        #expect(Json.double(confirmation["subtotal"]) == 4.0)
    }

    @Test("Starting over shows the restaurant list again")
    func startOver() throws {
        let agent = TestData.agent()
        _ = agent.respond(to: AgentRequest(contextId: "ctx", text: "chinese"))
        let response = agent.respond(
            to: AgentRequest(contextId: "ctx", rendererMessages: [action("startOver")])
        )

        #expect(try createSurface(in: response).surfaceId == "restaurants-2")
    }

    @Test("Conversations do not share surface numbering or selection")
    func sessionIsolation() throws {
        let agent = TestData.agent()
        _ = agent.respond(to: AgentRequest(contextId: "a", text: "chinese"))
        let other = agent.respond(to: AgentRequest(contextId: "b", text: "sushi"))

        #expect(try createSurface(in: other).surfaceId == "restaurants-1")
    }

    @Test("A request with nothing to do explains how to start")
    func emptyRequest() {
        let response = TestData.agent().respond(to: AgentRequest(contextId: "ctx"))

        #expect(response.messages.isEmpty)
        #expect(response.text?.isEmpty == false)
    }

    @Test("An unknown action is reported without breaking the conversation")
    func unknownAction() {
        let response = TestData.agent().respond(
            to: AgentRequest(contextId: "ctx", rendererMessages: [action("doTheThing")])
        )

        #expect(response.text?.contains("doTheThing") == true)
    }
}

@Suite("Agent side functions")
struct AgentFunctionTests {
    private func call(_ arguments: JsonMap) -> AgentResponse {
        TestData.agent().respond(
            to: AgentRequest(
                contextId: "ctx",
                rendererMessages: [
                    .callAgentFunction(
                        CallAgentFunctionMessage(
                            surfaceId: "order-1",
                            functionCallId: "call-1",
                            callFunction: FunctionCall(name: "deliveryEstimate", arguments: arguments)
                        )
                    )
                ]
            )
        )
    }

    @Test("deliveryEstimate answers pickup and delivery differently")
    func estimates() throws {
        let pickup = call(["restaurantId": "golden-dragon", "orderType": ["pickup"]])
        guard case let .agentFunctionResponse(pickupResponse) = try #require(pickup.messages.first) else {
            Issue.record("Expected an agentFunctionResponse")
            return
        }
        #expect(pickupResponse.functionCallId == "call-1")
        #expect(Json.string(pickupResponse.value) == "Ready for pickup in about 25 min")

        let delivery = call(["restaurantId": "golden-dragon", "orderType": ["delivery"]])
        guard case let .agentFunctionResponse(deliveryResponse) = try #require(delivery.messages.first) else {
            Issue.record("Expected an agentFunctionResponse")
            return
        }
        #expect(Json.string(deliveryResponse.value) == "Delivery in 35–45 min · $4.99 fee")
    }

    @Test("A plain string order type is accepted too")
    func scalarOrderType() throws {
        let response = call(["restaurantId": "golden-dragon", "orderType": "delivery"])
        guard case let .agentFunctionResponse(payload) = try #require(response.messages.first) else {
            Issue.record("Expected an agentFunctionResponse")
            return
        }
        #expect(Json.string(payload.value)?.contains("Delivery") == true)
    }

    @Test("An unknown restaurant produces a function error")
    func unknownRestaurant() throws {
        let response = call(["restaurantId": "nope"])
        guard case let .agentFunctionResponse(payload) = try #require(response.messages.first) else {
            Issue.record("Expected an agentFunctionResponse")
            return
        }
        #expect(payload.error?.code == "RESTAURANT_NOT_FOUND")
    }

    @Test("An unknown function is rejected with UNKNOWN_FUNCTION")
    func unknownFunction() throws {
        let response = TestData.agent().respond(
            to: AgentRequest(
                contextId: "ctx",
                rendererMessages: [
                    .callAgentFunction(
                        CallAgentFunctionMessage(
                            surfaceId: "order-1",
                            functionCallId: "call-2",
                            callFunction: FunctionCall(name: "mysteryFunction")
                        )
                    )
                ]
            )
        )
        guard case let .agentFunctionResponse(payload) = try #require(response.messages.first) else {
            Issue.record("Expected an agentFunctionResponse")
            return
        }
        #expect(payload.error?.code == "UNKNOWN_FUNCTION")
    }
}
