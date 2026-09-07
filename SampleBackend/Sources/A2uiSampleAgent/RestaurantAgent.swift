//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import GenUI

/// A request delivered to the sample agent.
public struct AgentRequest {
    /// The conversation the request belongs to.
    public let contextId: String

    /// The user's prompt, when the request carries one.
    public let text: String?

    /// Renderer-to-agent A2UI events carried by the request.
    public let rendererMessages: [RendererMessage]

    /// The catalogs the renderer supports.
    public let capabilities: RendererCapabilities?

    /// The current data models of surfaces that opted into synchronization.
    public let dataModel: RendererDataModel?

    /// Creates an agent request.
    /// The server builds these from incoming A2A messages.
    public init(
        contextId: String,
        text: String? = nil,
        rendererMessages: [RendererMessage] = [],
        capabilities: RendererCapabilities? = nil,
        dataModel: RendererDataModel? = nil
    ) {
        self.contextId = contextId
        self.text = text
        self.rendererMessages = rendererMessages
        self.capabilities = capabilities
        self.dataModel = dataModel
    }
}

/// The agent's answer to a request.
public struct AgentResponse {
    /// The A2UI messages to stream to the renderer.
    public var messages: [A2uiMessage]

    /// An optional text response shown next to the surface.
    public var text: String?

    /// Creates an agent response.
    public init(messages: [A2uiMessage] = [], text: String? = nil) {
        self.messages = messages
        self.text = text
    }
}

/// A deterministic A2UI agent that walks the user through a restaurant order.
///
/// The agent implements the full v1.0 loop without a language model, which
/// makes the sample reproducible and testable:
///
/// 1. a free-text prompt produces a searchable list of restaurants,
/// 2. `selectRestaurant` opens an order form with two-way bound inputs,
/// 3. `placeOrder` validates the order server side and renders a confirmation,
/// 4. the order form binds a value to `deliveryEstimate`, a function the
///    renderer does not know, so the renderer routes it back with
///    `callAgentFunction` and the agent answers with `agentFunctionResponse`.
///
/// The agent is safe to use from multiple connections; session state is
/// guarded by a lock.
public final class RestaurantAgent {
    /// The name advertised in the agent card.
    public static let name = "Restaurant Finder"

    /// The description advertised in the agent card.
    public static let description =
        "Finds restaurants and takes an order, rendering every step as A2UI v1.0 surfaces."

    /// The agent's version.
    public static let version = "1.0.0"

    private let data: RestaurantCatalog
    private let catalogId: String
    private let clock: () -> Date
    private let lock = NSLock()
    private var sessions: [String: Session] = [:]

    /// Creates an agent over a restaurant data set.
    /// Inject `clock` to make time-dependent output deterministic in tests.
    public init(
        data: RestaurantCatalog,
        catalogId: String = basicCatalogId,
        clock: @escaping () -> Date = Date.init
    ) {
        self.data = data
        self.catalogId = catalogId
        self.clock = clock
    }

    /// Creates an agent over the bundled sample data.
    /// Throws when the bundled data cannot be loaded.
    public convenience init() throws {
        self.init(data: try RestaurantCatalog())
    }

    /// The A2UI capabilities the agent advertises in its agent card.
    public var capabilities: AgentCapabilities {
        AgentCapabilities(supportedCatalogIds: [catalogId], acceptsInlineCatalogs: false)
    }

    /// Produces the response for a request.
    ///
    /// Function calls are answered first, because a renderer may batch a
    /// function call together with a user action in a single message.
    public func respond(to request: AgentRequest) -> AgentResponse {
        var response = AgentResponse()

        for message in request.rendererMessages {
            switch message {
            case let .callAgentFunction(call):
                response.messages.append(answer(call))
            case let .action(action):
                let actionResponse = handle(action, request: request)
                response.messages.append(contentsOf: actionResponse.messages)
                response.text = actionResponse.text ?? response.text
            case let .error(error):
                // A renderer error means the generated UI was not renderable.
                // A model-backed agent would repair the tree here; the sample
                // logs it so the problem is visible during development.
                print("[agent] renderer error \(error.code): \(error.message)")
            case let .rendererFunctionResponse(functionResponse):
                print("[agent] renderer function \(functionResponse.functionCallId) returned")
            }
        }

        if let text = request.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            let searchResponse = search(query: text, contextId: request.contextId)
            response.messages.append(contentsOf: searchResponse.messages)
            response.text = searchResponse.text
        }

        if response.messages.isEmpty && response.text == nil {
            response.text = "Tell me what you are in the mood for, for example \"dim sum in New York\"."
        }
        return response
    }

    // MARK: - Search

    private func search(query: String, contextId: String) -> AgentResponse {
        let results = data.search(query)
        let surfaceId = withSession(contextId) { session in
            session.selectedRestaurantId = nil
            return session.nextSurfaceId(prefix: "restaurants")
        }

        var messages = replacePreviousSurface(contextId: contextId, with: surfaceId)
        messages.append(
            .createSurface(
                CreateSurfaceMessage(
                    surfaceId: surfaceId,
                    catalogId: catalogId,
                    sendDataModel: false,
                    components: restaurantListComponents(query: query),
                    dataModel: [
                        "query": query,
                        "resultCount": results.count,
                        "restaurants": results.map(restaurantData)
                    ]
                )
            )
        )

        let names = results.prefix(3).map { $0.name }.joined(separator: ", ")
        return AgentResponse(
            messages: messages,
            text: results.isEmpty
                ? "I could not find a match, so here is everything I know about."
                : "Found \(results.count) places, including \(names). Pick one to start an order."
        )
    }

    private func restaurantListComponents(query: String) -> [Component] {
        [
            A2ui.column("root", ["listHeader", "restaurantList"], align: "stretch"),
            A2ui.text("listHeader", A2ui.format("### ${/resultCount} places for “${/query}”")),
            A2ui.list("restaurantList", A2ui.template("restaurantCard", path: "/restaurants")),
            A2ui.card("restaurantCard", child: "restaurantRow"),
            A2ui.row("restaurantRow", ["restaurantPhoto", "restaurantInfo"], align: "start"),
            A2ui.image(
                "restaurantPhoto",
                url: A2ui.path("imageUrl"),
                variant: "smallFeature",
                fit: "cover",
                description: A2ui.format("Photo of ${name}")
            ),
            A2ui.column("restaurantInfo", ["restaurantName", "restaurantCuisine", "restaurantRating", "orderButton"], weight: 1),
            A2ui.text("restaurantName", A2ui.format("**${name}**")),
            A2ui.text("restaurantCuisine", A2ui.format("${cuisine} · ${neighborhood}"), variant: "caption"),
            A2ui.row("restaurantRating", ["ratingIcon", "ratingText"], align: "center"),
            A2ui.icon("ratingIcon", "star"),
            A2ui.text(
                "ratingText",
                A2ui.format("${rating} (${reviewCount}) · ${priceRange} · ${distanceMiles} mi"),
                variant: "caption"
            ),
            A2ui.button(
                "orderButton",
                child: "orderButtonLabel",
                action: A2ui.event(
                    "selectRestaurant",
                    userMessage: A2ui.format("Start an order at ${name}"),
                    context: ["restaurantId": A2ui.path("id")]
                ),
                variant: "primary"
            ),
            A2ui.text("orderButtonLabel", "Start order")
        ]
    }

    // MARK: - Actions

    private func handle(_ action: RendererAction, request: AgentRequest) -> AgentResponse {
        switch action.name {
        case "selectRestaurant":
            guard let id = Json.string(action.context["restaurantId"]), let restaurant = data.restaurant(id: id) else {
                return AgentResponse(text: "I could not find that restaurant. Try another one.")
            }
            return openOrderForm(for: restaurant, contextId: request.contextId)
        case "placeOrder":
            return placeOrder(action: action, request: request)
        case "startOver":
            return search(query: "", contextId: request.contextId)
        default:
            return AgentResponse(text: "I do not know how to handle '\(action.name)' yet.")
        }
    }

    private func openOrderForm(for restaurant: Restaurant, contextId: String) -> AgentResponse {
        let surfaceId = withSession(contextId) { session in
            session.selectedRestaurantId = restaurant.id
            return session.nextSurfaceId(prefix: "order")
        }

        var messages = replacePreviousSurface(contextId: contextId, with: surfaceId)
        messages.append(
            .createSurface(
                CreateSurfaceMessage(
                    surfaceId: surfaceId,
                    catalogId: catalogId,
                    sendDataModel: true,
                    components: orderFormComponents(for: restaurant),
                    dataModel: [
                        "restaurant": restaurantData(restaurant),
                        "order": [
                            "items": [String](),
                            "type": ["pickup"],
                            "when": defaultPickupTime(for: restaurant),
                            "address": "",
                            "notes": "",
                            "utensils": true,
                            "error": ""
                        ] as JsonMap
                    ]
                )
            )
        )
        return AgentResponse(
            messages: messages,
            text: "Here is the menu for \(restaurant.name). Choose your dishes and place the order."
        )
    }

    private func orderFormComponents(for restaurant: Restaurant) -> [Component] {
        let options: [JsonMap] = restaurant.menu.map { item in
            [
                "label": "\(item.name) — \(Self.money(item.price))",
                "value": item.id
            ]
        }

        return [
            A2ui.column("root", ["heroCard", "menuCard", "detailsCard", "orderError", "actionsRow"], align: "stretch"),

            A2ui.card("heroCard", child: "heroColumn"),
            A2ui.column("heroColumn", ["heroImage", "heroTitle", "heroSubtitle", "heroEstimate"], align: "stretch"),
            A2ui.image(
                "heroImage",
                url: A2ui.path("/restaurant/imageUrl"),
                variant: "header",
                fit: "cover",
                description: A2ui.format("Photo of ${/restaurant/name}")
            ),
            A2ui.text("heroTitle", A2ui.format("### ${/restaurant/name}")),
            A2ui.text(
                "heroSubtitle",
                A2ui.format("${/restaurant/cuisine} · ${/restaurant/priceRange} · ${/restaurant/rating}★"),
                variant: "caption"
            ),
            // `deliveryEstimate` is not part of the renderer's catalog, so the
            // renderer routes it to the agent with `callAgentFunction`.
            A2ui.text(
                "heroEstimate",
                A2ui.call(
                    "deliveryEstimate",
                    [
                        "restaurantId": restaurant.id,
                        "orderType": A2ui.path("/order/type")
                    ]
                ),
                variant: "caption"
            ),

            A2ui.card("menuCard", child: "menuColumn"),
            A2ui.column("menuColumn", ["menuTitle", "menuPicker"], align: "stretch"),
            A2ui.text("menuTitle", "#### Choose your dishes"),
            A2ui.choicePicker(
                "menuPicker",
                options: options,
                value: A2ui.path("/order/items"),
                variant: "multipleSelection",
                displayStyle: "checkbox",
                checks: [
                    A2ui.check(
                        A2ui.call("required", ["value": A2ui.path("/order/items")]),
                        message: "Pick at least one dish."
                    )
                ]
            ),

            A2ui.card("detailsCard", child: "detailsColumn"),
            A2ui.column(
                "detailsColumn",
                ["detailsTitle", "typePicker", "whenInput", "addressField", "notesField", "utensilsCheck"],
                align: "stretch"
            ),
            A2ui.text("detailsTitle", "#### Order details"),
            A2ui.choicePicker(
                "typePicker",
                label: "How would you like it?",
                options: [
                    ["label": "Pickup", "value": "pickup"],
                    ["label": "Delivery", "value": "delivery"]
                ],
                value: A2ui.path("/order/type"),
                variant: "mutuallyExclusive",
                displayStyle: "chips"
            ),
            A2ui.dateTimeInput("whenInput", label: "When", value: A2ui.path("/order/when")),
            A2ui.textField(
                "addressField",
                label: "Delivery address",
                value: A2ui.path("/order/address"),
                placeholder: "Street, apartment, city"
            ),
            A2ui.textField(
                "notesField",
                label: "Notes for the kitchen",
                value: A2ui.path("/order/notes"),
                placeholder: "Allergies, spice level, ...",
                variant: "longText"
            ),
            A2ui.checkBox("utensilsCheck", label: "Include utensils", value: A2ui.path("/order/utensils")),

            A2ui.text("orderError", A2ui.path("/order/error"), variant: "caption"),

            A2ui.row("actionsRow", ["placeOrderButton", "backButton"], align: "center", justify: "spaceBetween"),
            A2ui.button(
                "placeOrderButton",
                child: "placeOrderLabel",
                action: A2ui.event(
                    "placeOrder",
                    userMessage: A2ui.format("Place the order at ${/restaurant/name}"),
                    context: [
                        "restaurantId": restaurant.id,
                        "items": A2ui.path("/order/items"),
                        "type": A2ui.path("/order/type"),
                        "when": A2ui.path("/order/when"),
                        "address": A2ui.path("/order/address"),
                        "notes": A2ui.path("/order/notes"),
                        "utensils": A2ui.path("/order/utensils")
                    ]
                ),
                variant: "primary",
                checks: [
                    A2ui.check(
                        A2ui.call(
                            "and",
                            [
                                "values": [
                                    A2ui.call("required", ["value": A2ui.path("/order/items")]),
                                    A2ui.call("required", ["value": A2ui.path("/order/when")])
                                ]
                            ]
                        ),
                        message: "Choose at least one dish and a time."
                    )
                ]
            ),
            A2ui.text("placeOrderLabel", "Place order"),
            A2ui.button(
                "backButton",
                child: "backLabel",
                action: A2ui.event("startOver", userMessage: "Show me other restaurants"),
                variant: "borderless"
            ),
            A2ui.text("backLabel", "Other restaurants")
        ]
    }

    private func placeOrder(action: RendererAction, request: AgentRequest) -> AgentResponse {
        let surfaceId = action.surfaceId
        let synchronized = request.dataModel?.surfaces[surfaceId]
        let order = Json.map(synchronized?["order"]) ?? [:]

        let restaurantId = Json.string(action.context["restaurantId"])
            ?? Json.string(Json.map(synchronized?["restaurant"])?["id"])
            ?? withSession(request.contextId) { $0.selectedRestaurantId }
        guard let restaurantId, let restaurant = data.restaurant(id: restaurantId) else {
            return AgentResponse(text: "I lost track of the restaurant. Let's start again.")
        }

        let itemIds = Json.stringArray(action.context["items"]) ?? Json.stringArray(order["items"]) ?? []
        let orderType = (Json.stringArray(action.context["type"]) ?? Json.stringArray(order["type"]) ?? ["pickup"]).first ?? "pickup"
        let address = Json.string(action.context["address"]) ?? Json.string(order["address"]) ?? ""
        let notes = Json.string(action.context["notes"]) ?? Json.string(order["notes"]) ?? ""
        let when = Json.string(action.context["when"]) ?? Json.string(order["when"]) ?? ""

        let items = restaurant.menu.filter { itemIds.contains($0.id) }
        if items.isEmpty {
            return validationFailure(
                surfaceId: surfaceId,
                message: "Pick at least one dish before placing the order."
            )
        }
        if orderType == "delivery", address.trimmingCharacters(in: .whitespacesAndNewlines).count < 5 {
            return validationFailure(
                surfaceId: surfaceId,
                message: "Add a delivery address, or switch to pickup."
            )
        }

        let subtotal = items.reduce(0) { $0 + $1.price }
        let deliveryFee = orderType == "delivery" ? Self.deliveryFee : 0
        let tax = ((subtotal + deliveryFee) * Self.taxRate * 100).rounded() / 100
        let total = subtotal + deliveryFee + tax
        let reference = Self.reference(for: restaurant, at: clock())

        let confirmationSurfaceId = withSession(request.contextId) { session in
            session.nextSurfaceId(prefix: "confirmation")
        }
        var messages = replacePreviousSurface(contextId: request.contextId, with: confirmationSurfaceId)
        messages.append(
            .createSurface(
                CreateSurfaceMessage(
                    surfaceId: confirmationSurfaceId,
                    catalogId: catalogId,
                    components: confirmationComponents(),
                    dataModel: [
                        "confirmation": [
                            "restaurantName": restaurant.name,
                            "reference": reference,
                            "headline": orderType == "delivery" ? "Order on the way" : "Order confirmed",
                            "eta": estimate(for: restaurant, orderType: orderType),
                            "when": when,
                            "fulfilment": orderType == "delivery" ? "Delivery to \(address)" : "Pickup at \(restaurant.name)",
                            "notes": notes,
                            "lines": items.map { item in
                                [
                                    "name": item.name,
                                    "price": item.price,
                                    "image": item.imageUrl ?? ""
                                ] as JsonMap
                            },
                            "subtotal": subtotal,
                            "deliveryFee": deliveryFee,
                            "tax": tax,
                            "total": total
                        ] as JsonMap
                    ]
                )
            )
        )

        return AgentResponse(
            messages: messages,
            text: "Your order at \(restaurant.name) is confirmed. Reference \(reference)."
        )
    }

    private func validationFailure(surfaceId: String, message: String) -> AgentResponse {
        AgentResponse(
            messages: [
                .updateDataModel(
                    UpdateDataModelMessage(
                        surfaceId: surfaceId,
                        path: DataPath("/order/error"),
                        value: message
                    )
                )
            ],
            text: message
        )
    }

    private func confirmationComponents() -> [Component] {
        [
            A2ui.card("root", child: "confirmationColumn"),
            A2ui.column(
                "confirmationColumn",
                [
                    "confirmationHeader", "confirmationEta", "confirmationFulfilment",
                    "lineItems", "totalsDivider", "subtotalRow", "feeRow", "taxRow", "totalRow",
                    "confirmationReference", "againButton"
                ],
                align: "stretch"
            ),
            A2ui.row("confirmationHeader", ["confirmationIcon", "confirmationTitle"], align: "center"),
            A2ui.icon("confirmationIcon", "check"),
            A2ui.text("confirmationTitle", A2ui.format("### ${/confirmation/headline}")),
            A2ui.text("confirmationEta", A2ui.path("/confirmation/eta")),
            A2ui.text("confirmationFulfilment", A2ui.path("/confirmation/fulfilment"), variant: "caption"),

            A2ui.list("lineItems", A2ui.template("lineItemRow", path: "/confirmation/lines")),
            A2ui.row("lineItemRow", ["lineItemPhoto", "lineItemName", "lineItemPrice"], align: "center"),
            A2ui.image(
                "lineItemPhoto",
                url: A2ui.path("image"),
                variant: "smallFeature",
                fit: "cover",
                description: A2ui.format("Photo of ${name}")
            ),
            A2ui.text("lineItemName", A2ui.format("${@index(offset: 1)}. ${name}"), weight: 1),
            A2ui.text("lineItemPrice", A2ui.currency(A2ui.path("price"))),

            A2ui.divider("totalsDivider"),
            A2ui.row("subtotalRow", ["subtotalLabel", "subtotalValue"], justify: "spaceBetween"),
            A2ui.text("subtotalLabel", "Subtotal", variant: "caption"),
            A2ui.text("subtotalValue", A2ui.currency(A2ui.path("/confirmation/subtotal"))),
            A2ui.row("feeRow", ["feeLabel", "feeValue"], justify: "spaceBetween"),
            A2ui.text("feeLabel", "Delivery", variant: "caption"),
            A2ui.text("feeValue", A2ui.currency(A2ui.path("/confirmation/deliveryFee"))),
            A2ui.row("taxRow", ["taxLabel", "taxValue"], justify: "spaceBetween"),
            A2ui.text("taxLabel", "Tax", variant: "caption"),
            A2ui.text("taxValue", A2ui.currency(A2ui.path("/confirmation/tax"))),
            A2ui.row("totalRow", ["totalLabel", "totalValue"], justify: "spaceBetween"),
            A2ui.text("totalLabel", "**Total**"),
            A2ui.text("totalValue", A2ui.currency(A2ui.path("/confirmation/total"))),

            A2ui.text("confirmationReference", A2ui.format("Reference ${/confirmation/reference}"), variant: "caption"),
            A2ui.button(
                "againButton",
                child: "againLabel",
                action: A2ui.event("startOver", userMessage: "Find another restaurant"),
                variant: "borderless"
            ),
            A2ui.text("againLabel", "Order somewhere else")
        ]
    }

    // MARK: - Agent functions

    private func answer(_ call: CallAgentFunctionMessage) -> A2uiMessage {
        switch call.callFunction.name {
        case "deliveryEstimate":
            let restaurantId = Json.string(call.callFunction.arguments["restaurantId"]) ?? ""
            let orderType = (Json.stringArray(call.callFunction.arguments["orderType"])
                ?? [Json.string(call.callFunction.arguments["orderType"]) ?? "pickup"]).first ?? "pickup"
            guard let restaurant = data.restaurant(id: restaurantId) else {
                return .agentFunctionResponse(
                    FunctionResponse(
                        functionCallId: call.functionCallId,
                        error: FunctionResponse.Failure(
                            code: "RESTAURANT_NOT_FOUND",
                            message: "No restaurant with id '\(restaurantId)'."
                        )
                    )
                )
            }
            return .agentFunctionResponse(
                FunctionResponse(
                    functionCallId: call.functionCallId,
                    value: estimate(for: restaurant, orderType: orderType)
                )
            )
        default:
            return .agentFunctionResponse(
                FunctionResponse(
                    functionCallId: call.functionCallId,
                    error: FunctionResponse.Failure(
                        code: RendererError.Code.unknownFunction,
                        message: "This agent does not provide '\(call.callFunction.name)'."
                    )
                )
            )
        }
    }

    /// The human-readable fulfilment estimate for a restaurant.
    /// Exposed so tests can assert on the same text the UI shows.
    public func estimate(for restaurant: Restaurant, orderType: String) -> String {
        if orderType == "delivery" {
            let low = restaurant.prepMinutes + 10
            let high = restaurant.prepMinutes + 20
            return "Delivery in \(low)–\(high) min · \(Self.money(Self.deliveryFee)) fee"
        }
        return "Ready for pickup in about \(restaurant.prepMinutes) min"
    }

    // MARK: - Session state

    private final class Session {
        var selectedRestaurantId: String?
        var currentSurfaceId: String?
        var surfaceCounter = 0

        func nextSurfaceId(prefix: String) -> String {
            surfaceCounter += 1
            return "\(prefix)-\(surfaceCounter)"
        }
    }

    private func withSession<T>(_ contextId: String, _ body: (Session) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        let session = sessions[contextId] ?? Session()
        sessions[contextId] = session
        return body(session)
    }

    /// Deletes the surface currently on screen before creating a new one.
    ///
    /// Surface ids must be unique for the renderer's lifetime, so the agent
    /// never reuses one; it deletes the old surface instead.
    private func replacePreviousSurface(contextId: String, with newSurfaceId: String) -> [A2uiMessage] {
        withSession(contextId) { session in
            var messages: [A2uiMessage] = []
            if let previous = session.currentSurfaceId {
                messages.append(.deleteSurface(DeleteSurfaceMessage(surfaceId: previous)))
            }
            session.currentSurfaceId = newSurfaceId
            return messages
        }
    }

    // MARK: - Helpers

    private static let taxRate = 0.0875
    private static let deliveryFee = 4.99

    private func restaurantData(_ restaurant: Restaurant) -> JsonMap {
        [
            "id": restaurant.id,
            "name": restaurant.name,
            "cuisine": restaurant.cuisine,
            "city": restaurant.city,
            "neighborhood": restaurant.neighborhood,
            "rating": restaurant.rating,
            "reviewCount": restaurant.reviewCount,
            "priceRange": restaurant.priceRange,
            "distanceMiles": restaurant.distanceMiles,
            "prepMinutes": restaurant.prepMinutes,
            "imageUrl": restaurant.imageUrl
        ]
    }

    private func defaultPickupTime(for restaurant: Restaurant) -> String {
        let date = clock().addingTimeInterval(TimeInterval(restaurant.prepMinutes * 60))
        return A2uiTimestamp.string(from: date)
    }

    private static func money(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private static func reference(for restaurant: Restaurant, at date: Date) -> String {
        let prefix = restaurant.id.prefix(3).uppercased()
        let stamp = Int(date.timeIntervalSince1970) % 100_000
        return "\(prefix)-\(stamp)"
    }
}
