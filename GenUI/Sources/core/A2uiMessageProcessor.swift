//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Combine
import Foundation

/// Applies A2UI messages to renderer state and produces the events to send back.
///
/// The processor is the heart of the renderer: it owns one ``SurfaceViewModel``
/// per surface, applies `createSurface`, `updateComponents`, `updateDataModel`
/// and `deleteSurface` messages, executes agent-initiated renderer function
/// calls, and routes function calls the renderer cannot resolve locally to the
/// agent.
///
/// All members must be used from the main thread; the transport delivers
/// messages there.
public final class A2uiMessageProcessor: GenUiHost, RemoteFunctionRouter {
    /// The catalogs this renderer supports.
    public let catalogs: CatalogRegistry

    /// Host capabilities passed to components and functions.
    public let services: RendererServices

    private var surfaces: [String: SurfaceViewModel] = [:]
    private var surfaceOrder: [String] = []
    private let surfaceUpdatesSubject = PassthroughSubject<GenUiUpdate, Never>()
    private let rendererMessagesSubject = PassthroughSubject<RendererMessage, Never>()
    private var remoteCalls: [RemoteCallKey: RemoteCallState] = [:]
    private var remoteCallIds: [String: RemoteCallKey] = [:]
    private var reportedErrors: Set<String> = []
    private var callIdCounter = 0

    /// Creates a processor for the given catalogs.
    ///
    /// Pass `defaultCatalogId` to keep rendering surfaces from agents that
    /// omit `catalogId`; without it, such surfaces fail to resolve, as the
    /// specification requires.
    public init(
        catalogs: [Catalog],
        defaultCatalogId: String? = nil,
        services: RendererServices = .default
    ) {
        self.catalogs = CatalogRegistry(catalogs: catalogs, defaultCatalogId: defaultCatalogId)
        self.services = services
    }

    // MARK: - Streams

    /// A stream of surface lifecycle changes.
    public var surfaceUpdates: AnyPublisher<GenUiUpdate, Never> {
        surfaceUpdatesSubject.eraseToAnyPublisher()
    }

    /// A stream of messages that must be delivered to the agent.
    ///
    /// Includes user actions, renderer function responses, renderer-initiated
    /// agent function calls and renderer errors.
    public var rendererMessages: AnyPublisher<RendererMessage, Never> {
        rendererMessagesSubject.eraseToAnyPublisher()
    }

    /// A stream of user actions, for hosts that only care about interactions.
    public var actions: AnyPublisher<RendererAction, Never> {
        rendererMessagesSubject
            .compactMap { message in
                guard case let .action(action) = message else { return nil }
                return action
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Surfaces

    /// The ids of all live surfaces, in creation order.
    public var surfaceIds: [String] {
        surfaceOrder.filter { surfaces[$0]?.definition != nil }
    }

    /// Returns the observable state of a surface, creating it if needed.
    /// Views may bind to a surface before the agent creates it.
    public func surfaceViewModel(_ surfaceId: String) -> SurfaceViewModel {
        if let existing = surfaces[surfaceId] {
            return existing
        }
        let viewModel = SurfaceViewModel(surfaceId: surfaceId)
        surfaces[surfaceId] = viewModel
        if !surfaceOrder.contains(surfaceId) {
            surfaceOrder.append(surfaceId)
        }
        return viewModel
    }

    /// The data model of a surface, creating the surface state if needed.
    public func dataModel(for surfaceId: String) -> DataModel {
        surfaceViewModel(surfaceId).dataModel
    }

    /// A snapshot of the data models of all surfaces that opted into syncing.
    ///
    /// Attached to outgoing agent messages for surfaces created with
    /// `sendDataModel: true`.
    public func synchronizedDataModel() -> RendererDataModel {
        var payload: [String: JsonMap] = [:]
        for (surfaceId, viewModel) in surfaces {
            guard let definition = viewModel.definition, definition.sendDataModel else { continue }
            payload[surfaceId] = viewModel.dataModel.snapshot
        }
        return RendererDataModel(surfaces: payload)
    }

    /// Removes every surface and its data.
    /// Emits removal updates unless `emitUpdates` is `false`.
    public func clearSurfaces(emitUpdates: Bool = true) {
        let ids = surfaceOrder
        surfaces.removeAll()
        surfaceOrder.removeAll()
        remoteCalls.removeAll()
        remoteCallIds.removeAll()
        reportedErrors.removeAll()
        guard emitUpdates else { return }
        for surfaceId in ids {
            surfaceUpdatesSubject.send(SurfaceRemoved(surfaceId: surfaceId))
        }
    }

    /// Releases all surface state.
    /// Call when the processor is no longer needed.
    public func dispose() {
        clearSurfaces(emitUpdates: false)
    }

    // MARK: - Message handling

    /// Applies an A2UI message to renderer state.
    ///
    /// Messages targeting an unknown surface are reported to the agent instead
    /// of being silently dropped, which is what lets an agent recover.
    public func handle(_ message: A2uiMessage) {
        switch message {
        case let .createSurface(message):
            createSurface(message)
        case let .updateComponents(message):
            updateComponents(message)
        case let .updateDataModel(message):
            updateDataModel(message)
        case let .deleteSurface(message):
            deleteSurface(message)
        case let .callRendererFunction(message):
            callRendererFunction(message)
        case let .agentFunctionResponse(response):
            resolveAgentFunction(response)
        }
    }

    /// Applies a list of messages in order.
    ///
    /// A failing message does not stop the rest of the list, matching the A2A
    /// binding's processing rules.
    public func handle(_ messages: [A2uiMessage]) {
        for message in messages {
            handle(message)
        }
    }

    private func createSurface(_ message: CreateSurfaceMessage) {
        let viewModel = surfaceViewModel(message.surfaceId)
        if viewModel.definition != nil {
            genUiLogger.warning(
                "Surface '\(message.surfaceId)' already exists and is being replaced. "
                    + "Surface ids must be unique for the renderer's lifetime."
            )
        }

        var definition = UiDefinition(
            surfaceId: message.surfaceId,
            catalogId: message.catalogId,
            sendDataModel: message.sendDataModel,
            metadata: message.metadata
        )
        definition.merge(message.components)

        if catalogs.resolveCatalog(entityCatalogId: nil, surfaceCatalogId: message.catalogId) == nil {
            report(
                RendererError(
                    code: RendererError.Code.unknownCatalog,
                    message: "Surface '\(message.surfaceId)' requested catalog "
                        + "'\(message.catalogId ?? "<none>")', which this renderer does not support. "
                        + "Supported catalogs: \(catalogs.supportedCatalogIds.joined(separator: ", ")).",
                    surfaceId: message.surfaceId
                )
            )
        }

        viewModel.create(definition: definition, dataModel: message.dataModel)
        genUiLogger.info("Created surface '\(message.surfaceId)'.")
        surfaceUpdatesSubject.send(SurfaceAdded(surfaceId: message.surfaceId, definition: definition))
    }

    private func updateComponents(_ message: UpdateComponentsMessage) {
        guard let viewModel = surfaces[message.surfaceId], viewModel.definition != nil else {
            report(
                RendererError(
                    code: RendererError.Code.unknownSurface,
                    message: "Cannot update components of surface '\(message.surfaceId)' because it was not created.",
                    surfaceId: message.surfaceId
                )
            )
            return
        }
        viewModel.merge(components: message.components)
        guard let definition = viewModel.definition else { return }
        genUiLogger.info("Updated \(message.components.count) component(s) on surface '\(message.surfaceId)'.")
        surfaceUpdatesSubject.send(SurfaceUpdated(surfaceId: message.surfaceId, definition: definition))
    }

    private func updateDataModel(_ message: UpdateDataModelMessage) {
        guard let viewModel = surfaces[message.surfaceId], let definition = viewModel.definition else {
            report(
                RendererError(
                    code: RendererError.Code.unknownSurface,
                    message: "Cannot update the data model of surface '\(message.surfaceId)' because it was not created.",
                    surfaceId: message.surfaceId
                )
            )
            return
        }
        viewModel.update(path: message.path, value: message.value)
        genUiLogger.info("Updated data model of surface '\(message.surfaceId)' at '\(message.path)'.")
        surfaceUpdatesSubject.send(SurfaceUpdated(surfaceId: message.surfaceId, definition: definition))
    }

    private func deleteSurface(_ message: DeleteSurfaceMessage) {
        guard surfaces.removeValue(forKey: message.surfaceId) != nil else { return }
        surfaceOrder.removeAll { $0 == message.surfaceId }
        let staleCalls = remoteCalls.keys.filter { $0.surfaceId == message.surfaceId }
        for key in staleCalls {
            remoteCalls.removeValue(forKey: key)
        }
        remoteCallIds = remoteCallIds.filter { !staleCalls.contains($0.value) }
        genUiLogger.info("Deleted surface '\(message.surfaceId)'.")
        surfaceUpdatesSubject.send(SurfaceRemoved(surfaceId: message.surfaceId))
    }

    // MARK: - Functions

    private func callRendererFunction(_ message: CallRendererFunctionMessage) {
        let call = message.callFunction
        guard let definition = catalogs.function(named: call.name, catalogId: call.catalogId) else {
            send(
                .error(
                    RendererError(
                        code: RendererError.Code.unknownFunction,
                        message: "Function '\(call.name)' is not registered with this renderer.",
                        functionCallId: message.functionCallId
                    )
                )
            )
            return
        }
        guard definition.isAgentCallable else {
            send(
                .error(
                    RendererError(
                        code: RendererError.Code.invalidFunctionCall,
                        message: "Function '\(call.name)' is rendererOnly and cannot be invoked remotely.",
                        functionCallId: message.functionCallId
                    )
                )
            )
            return
        }

        let evaluator = ExpressionEvaluator(
            catalogs: catalogs,
            surfaceId: "",
            surfaceCatalogId: call.catalogId,
            services: services,
            remoteRouter: self
        )
        let context = DataContext(DataModel(), "/")
        do {
            let arguments = evaluator.resolveArguments(call.arguments, in: context)
            let value = try definition.implementation(
                FunctionInvocation(
                    name: definition.name,
                    arguments: arguments,
                    context: context,
                    services: services,
                    evaluator: evaluator
                )
            )
            send(.rendererFunctionResponse(FunctionResponse(functionCallId: message.functionCallId, value: value)))
        } catch {
            let description = A2uiErrorFormatter.describe(error)
            let code = (error as? A2uiFunctionError)?.code ?? RendererError.Code.executionFailed
            send(
                .rendererFunctionResponse(
                    FunctionResponse(
                        functionCallId: message.functionCallId,
                        error: FunctionResponse.Failure(code: code, message: description)
                    )
                )
            )
        }
    }

    private func resolveAgentFunction(_ response: FunctionResponse) {
        guard let key = remoteCallIds.removeValue(forKey: response.functionCallId) else {
            genUiLogger.warning("Received a response for unknown function call '\(response.functionCallId)'.")
            return
        }
        if let error = response.error {
            genUiLogger.severe("Agent function '\(key.name)' failed: \(error.code) \(error.message)")
            remoteCalls[key] = .failed
        } else {
            remoteCalls[key] = .resolved(Json.normalized(response.value))
        }
        surfaces[key.surfaceId]?.touch()
    }

    /// Returns the agent's answer for a call, dispatching it when needed.
    ///
    /// The first evaluation returns `nil` and sends a `callAgentFunction`
    /// message; once the response arrives the surface is re-rendered and the
    /// cached value is returned.
    public func agentFunctionValue(
        for name: String,
        catalogId: String?,
        arguments: [String: Any],
        surfaceId: String
    ) -> Any? {
        let key = RemoteCallKey(
            surfaceId: surfaceId,
            name: name,
            catalogId: catalogId,
            arguments: Json.canonicalString(arguments)
        )
        switch remoteCalls[key] {
        case let .resolved(value):
            return value
        case .pending, .failed:
            return nil
        case nil:
            callIdCounter += 1
            let callId = "\(name)-\(callIdCounter)-\(UUID().uuidString.prefix(8))"
            remoteCalls[key] = .pending(callId)
            remoteCallIds[callId] = key
            genUiLogger.info("Routing function '\(name)' to the agent as call '\(callId)'.")
            send(
                .callAgentFunction(
                    CallAgentFunctionMessage(
                        surfaceId: surfaceId,
                        functionCallId: callId,
                        callFunction: FunctionCall(name: name, catalogId: catalogId, arguments: arguments)
                    )
                )
            )
            return nil
        }
    }

    // MARK: - Events

    /// Forwards a user action to the agent.
    public func handle(_ action: RendererAction) {
        send(.action(action))
    }

    /// Reports a renderer-side error to the agent, at most once per problem.
    ///
    /// Rendering runs on every state change, so identical errors are collapsed
    /// to keep the agent's context clean.
    public func report(_ error: RendererError) {
        let key = [error.code, error.message, error.surfaceId ?? "", error.path ?? ""].joined(separator: "|")
        guard reportedErrors.insert(key).inserted else { return }
        send(.error(error))
    }

    /// Emits a message for delivery to the agent.
    /// Exposed so hosts can inject synthetic events in tests.
    public func send(_ message: RendererMessage) {
        rendererMessagesSubject.send(message)
    }

    // MARK: - Remote call bookkeeping

    private struct RemoteCallKey: Hashable {
        let surfaceId: String
        let name: String
        let catalogId: String?
        let arguments: String
    }

    private enum RemoteCallState {
        case pending(String)
        case resolved(Any?)
        case failed
    }
}
