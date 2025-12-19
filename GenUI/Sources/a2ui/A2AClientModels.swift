//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Defines the transport surface for A2A JSON-RPC interactions.
/// Implementations fetch agent cards and send messages over HTTP or other channels.
public protocol A2AClientProtocol {
    /// Loads the agent card and returns parsed metadata.
    /// Use this to discover the RPC endpoint and supported capabilities.
    func getAgentCard() async throws -> A2AAgentCard

    /// Starts a `message/stream` request and yields SSE events.
    /// The stream ends when the server closes the connection or an error occurs.
    func sendMessageStream(_ payload: A2AMessageSendParams) -> AsyncThrowingStream<A2ASendStreamMessageResponse, Error>

    /// Sends a `message/send` request and waits for completion.
    /// Throws if the RPC call fails or returns an error response.
    func sendMessage(_ payload: A2AMessageSendParams) async throws
}

/// Supplies authentication headers and retry logic for A2A requests.
/// Implement this to inject tokens and refresh them on authentication failures.
public protocol A2AAuthenticationHandler {
    var headers: [String: String] { get async }

    /// Decides whether a failed request should be retried with new headers.
    /// Return updated headers to retry, or nil to propagate the error.
    func shouldRetryWithHeaders(
        request: URLRequest,
        response: HTTPURLResponse,
        body: Data?
    ) async -> [String: String]?

    /// Notifies the handler after a successful retry.
    /// Use this to persist refreshed credentials.
    func onSuccessfulRetry(_ headers: [String: String]) async
}

/// Describes optional features advertised by an A2A agent.
/// Check these flags before attempting streaming or push notifications.
public struct A2AAgentCapabilities {
    public let streaming: Bool?
    public let pushNotifications: Bool?

    /// Creates a capabilities container with optional flags.
    /// Use nil when the agent card omits a capability.
    public init(streaming: Bool? = nil, pushNotifications: Bool? = nil) {
        self.streaming = streaming
        self.pushNotifications = pushNotifications
    }

    /// Builds capabilities from a JSON map.
    /// Missing fields are treated as `nil`.
    public static func fromJson(_ json: JsonMap) -> A2AAgentCapabilities {
        A2AAgentCapabilities(
            streaming: json["streaming"] as? Bool,
            pushNotifications: json["pushNotifications"] as? Bool
        )
    }

    /// Serializes the capabilities to a JSON map.
    /// Omits fields that are `nil`.
    public func toJson() -> JsonMap {
        var json: JsonMap = [:]
        if let streaming { json["streaming"] = streaming }
        if let pushNotifications { json["pushNotifications"] = pushNotifications }
        return json
    }
}

/// Describes an A2A agent-card document.
/// Includes display metadata, endpoint URL, and capability flags.
public struct A2AAgentCard {
    public let name: String
    public let description: String
    public let version: String
    public let url: String
    public let capabilities: A2AAgentCapabilities?

    /// Creates a fully populated agent card.
    /// Prefer `fromJson` when parsing server responses.
    public init(
        name: String,
        description: String,
        version: String,
        url: String,
        capabilities: A2AAgentCapabilities? = nil
    ) {
        self.name = name
        self.description = description
        self.version = version
        self.url = url
        self.capabilities = capabilities
    }

    /// Parses an agent card response.
    /// Throws if the response is missing a usable endpoint URL.
    public static func fromJson(_ json: JsonMap) throws -> A2AAgentCard {
        let url = json["url"] as? String ?? ""
        if url.isEmpty {
            throw A2AClientError.invalidAgentCard
        }
        let capabilitiesJson = json["capabilities"] as? JsonMap
        return A2AAgentCard(
            name: json["name"] as? String ?? "",
            description: json["description"] as? String ?? "",
            version: json["version"] as? String ?? "",
            url: url,
            capabilities: capabilitiesJson.map { A2AAgentCapabilities.fromJson($0) }
        )
    }
}

/// Encodes a JSON-RPC 2.0 request for A2A endpoints.
/// Carries the method name, request id, and parameters.
public struct A2AJsonRpcRequest {
    public let jsonrpc: String
    public let method: String
    public let id: Int
    public let params: JsonMap

    /// Creates a JSON-RPC request wrapper.
    /// Uses the JSON-RPC 2.0 protocol version.
    public init(method: String, id: Int, params: JsonMap) {
        self.jsonrpc = "2.0"
        self.method = method
        self.id = id
        self.params = params
    }

    /// Serializes the request to a JSON map.
    /// This payload is sent to the A2A endpoint.
    public func toJson() -> JsonMap {
        [
            "jsonrpc": jsonrpc,
            "method": method,
            "id": id,
            "params": params
        ]
    }
}

/// Base protocol for parts inside an A2A message.
/// Concrete parts encode text, structured data, or files.
public protocol A2APart {
    /// Serializes the part to a JSON map.
    /// The result is used as the wire-format payload.
    func toJson() -> JsonMap
}

/// Message part containing plain text.
/// Encoded with a `"type": "text"` discriminator.
public struct A2ATextPart: A2APart {
    public var text: String

    /// Creates a text part with optional content.
    /// Defaults to an empty string.
    public init(text: String = "") {
        self.text = text
    }

    /// Serializes the part to a JSON map.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        ["kind": "text", "type": "text", "text": text]
    }

    /// Parses a text part from a JSON map.
    /// Returns nil if the payload is not a text part.
    public static func fromJson(_ json: JsonMap) -> A2ATextPart? {
        let kind = (json["type"] as? String) ?? (json["kind"] as? String)
        guard kind == "text" else { return nil }
        return A2ATextPart(text: json["text"] as? String ?? "")
    }
}

/// Message part containing structured data.
/// Encoded with a `"type": "data"` discriminator.
public struct A2ADataPart: A2APart {
    public var data: JsonMap

    public var metadata: JsonMap?

    /// Creates a data part with an optional JSON payload.
    /// Include metadata such as a mime type when needed.
    public init(data: JsonMap = [:], metadata: JsonMap? = nil) {
        self.data = data
        self.metadata = metadata
    }

    /// Serializes the part to a JSON map.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        var json: JsonMap = ["kind": "data", "type": "data", "data": data]
        if let metadata {
            json["metadata"] = metadata
            if let mimeType = metadata["mimeType"] as? String {
                json["mimeType"] = mimeType
            }
        }
        return json
    }

    /// Parses a data part from a JSON map.
    /// Returns nil if the payload is not a data part.
    public static func fromJson(_ json: JsonMap) -> A2ADataPart? {
        let kind = (json["type"] as? String) ?? (json["kind"] as? String)
        guard kind == "data" else { return nil }
        guard let data = json["data"] as? JsonMap else { return nil }
        var metadata = json["metadata"] as? JsonMap
        if let mimeType = json["mimeType"] as? String {
            if metadata == nil { metadata = [:] }
            metadata?["mimeType"] = mimeType
        }
        return A2ADataPart(data: data, metadata: metadata)
    }
}

/// Message part describing an attached file.
/// Wraps either a URI reference or base64-encoded bytes.
public struct A2AFilePart: A2APart {
    public var file: A2AFile

    /// Creates a file part for the provided file payload.
    /// Provide either a URI or base64 bytes representation.
    public init(file: A2AFile) {
        self.file = file
    }

    /// Serializes the part to a JSON map.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        ["kind": "file", "type": "file", "file": file.toJson()]
    }

    /// Parses a file part from a JSON map.
    /// Returns nil if the payload is not a file part.
    public static func fromJson(_ json: JsonMap) -> A2AFilePart? {
        let kind = (json["type"] as? String) ?? (json["kind"] as? String)
        guard kind == "file" else { return nil }
        guard let fileJson = json["file"] as? JsonMap else { return nil }
        if let uri = fileJson["uri"] as? String {
            let mimeType = fileJson["mimeType"] as? String ?? ""
            return A2AFilePart(file: A2AFileWithUri(uri: uri, mimeType: mimeType))
        }
        if let bytes = fileJson["bytes"] as? String {
            let mimeType = fileJson["mimeType"] as? String ?? ""
            return A2AFilePart(file: A2AFileWithBytes(bytes: bytes, mimeType: mimeType))
        }
        return nil
    }
}

/// Protocol for A2A file payload encodings.
/// Implementations serialize either a URI or inline bytes.
public protocol A2AFile {
    /// Serializes the file payload to a JSON map.
    /// Used when sending A2A file parts.
    func toJson() -> JsonMap
}

/// File payload that references a remote URI.
/// Use this when the file is hosted elsewhere.
public struct A2AFileWithUri: A2AFile {
    public var uri: String
    public var mimeType: String

    /// Creates a URI-based file payload.
    /// Provide the URI and associated MIME type.
    public init(uri: String, mimeType: String) {
        self.uri = uri
        self.mimeType = mimeType
    }

    /// Serializes the payload to a JSON map.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        ["uri": uri, "mimeType": mimeType]
    }
}

/// File payload carrying base64-encoded bytes.
/// Use this when you need inline file transfer.
public struct A2AFileWithBytes: A2AFile {
    public var bytes: String
    public var mimeType: String

    /// Creates a bytes-based file payload.
    /// Provide base64 bytes and the associated MIME type.
    public init(bytes: String, mimeType: String) {
        self.bytes = bytes
        self.mimeType = mimeType
    }

    /// Serializes the payload to a JSON map.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        ["bytes": bytes, "mimeType": mimeType]
    }
}

/// Marker protocol for A2A result payloads.
/// Implemented by message, task, and status update types.
public protocol A2AResult {
    /// Serializes the result to a JSON map.
    /// Used for logging or transport.
    func toJson() -> JsonMap
}

/// A2A message envelope containing role and parts.
/// Supports task references, context ids, and metadata payloads.
public struct A2AMessage: A2AResult {
    public var messageId: String
    public var role: String
    public var parts: [A2APart]
    public var referenceTaskIds: [String]?
    public var taskId: String?
    public var contextId: String?
    public var metadata: JsonMap?

    /// Creates a message with optional task and context metadata.
    /// Defaults the role to `"user"` and generates a message id.
    public init(
        messageId: String = UUID().uuidString,
        role: String = "user",
        parts: [A2APart] = [],
        referenceTaskIds: [String]? = nil,
        taskId: String? = nil,
        contextId: String? = nil,
        metadata: JsonMap? = nil
    ) {
        self.messageId = messageId
        self.role = role
        self.parts = parts
        self.referenceTaskIds = referenceTaskIds
        self.taskId = taskId
        self.contextId = contextId
        self.metadata = metadata
    }

    /// Parses a message from a JSON map.
    /// Unknown or unsupported parts are ignored.
    public static func fromJson(_ json: JsonMap) -> A2AMessage {
        let partsArray = json["parts"] as? [Any] ?? []
        let parts: [A2APart] = partsArray.compactMap { entry in
            guard let partJson = entry as? JsonMap else { return nil }
            if let text = A2ATextPart.fromJson(partJson) { return text }
            if let data = A2ADataPart.fromJson(partJson) { return data }
            if let file = A2AFilePart.fromJson(partJson) { return file }
            return nil
        }
        return A2AMessage(
            messageId: json["messageId"] as? String ?? "",
            role: json["role"] as? String ?? "",
            parts: parts,
            referenceTaskIds: json["referenceTaskIds"] as? [String],
            taskId: json["taskId"] as? String,
            contextId: json["contextId"] as? String,
            metadata: json["metadata"] as? JsonMap
        )
    }

    /// Serializes the message to a JSON map.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        var json: JsonMap = [
            "messageId": messageId,
            "role": role,
            "kind": "message",
            "parts": parts.map { $0.toJson() }
        ]
        if let referenceTaskIds {
            json["referenceTaskIds"] = referenceTaskIds
        }
        if let taskId {
            json["taskId"] = taskId
        }
        if let contextId {
            json["contextId"] = contextId
        }
        if let metadata {
            json["metadata"] = metadata
        }
        return json
    }
}

/// Parameters for `message/send` and `message/stream`.
/// Wraps the message plus optional extension identifiers.
public struct A2AMessageSendParams {
    public var message: A2AMessage
    public var extensions: [String]

    /// Creates send parameters with optional extension ids.
    /// Extensions are sent via the `X-A2A-Extensions` header.
    public init(message: A2AMessage, extensions: [String] = []) {
        self.message = message
        self.extensions = extensions
    }

    /// Serializes the parameters to a JSON map.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        var json: JsonMap = ["message": message.toJson()]
        if !extensions.isEmpty {
            json["extensions"] = extensions
        }
        return json
    }
}

/// Base protocol for SSE responses from `message/stream`.
/// Use `isError` to differentiate error and success events.
public protocol A2ASendStreamMessageResponse {
    var isError: Bool { get }
    func toJson() -> JsonMap
}

/// Streaming event that carries a JSON-RPC error.
/// Use when the SSE payload includes an error response.
public struct A2AJSONRPCErrorResponseSSM: A2ASendStreamMessageResponse {
    public var error: A2AError?
    public var id: Int?

    /// Creates an error response wrapper.
    /// Provide the parsed error and optional response id.
    public init(error: A2AError? = nil, id: Int? = nil) {
        self.error = error
        self.id = id
    }

    public var isError: Bool { true }

    /// Serializes the response to a JSON map.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        ["error": error?.toJson() as Any, "id": id as Any]
    }
}

/// Streaming event that carries a successful result.
/// The result may be a message, task, or status update.
public struct A2ASendStreamMessageSuccessResponse: A2ASendStreamMessageResponse {
    public var result: A2AResult?
    public var id: Int?

    /// Creates a success response wrapper.
    /// Provide the result and optional response id.
    public init(result: A2AResult? = nil, id: Int? = nil) {
        self.result = result
        self.id = id
    }

    public var isError: Bool { false }

    /// Serializes the response to a JSON map.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        ["result": result?.toJson() as Any, "id": id as Any]
    }
}

/// JSON-RPC error payload returned by the A2A server.
/// Carries the error code and human-readable message.
public struct A2AError {
    public var rpcErrorCode: Int?
    public var message: String?

    /// Creates an error payload with optional fields.
    /// Use nil values to omit fields.
    public init(rpcErrorCode: Int? = nil, message: String? = nil) {
        self.rpcErrorCode = rpcErrorCode
        self.message = message
    }

    /// Parses an error object from a JSON map.
    /// Missing fields are treated as nil.
    public static func fromJson(_ json: JsonMap) -> A2AError {
        A2AError(
            rpcErrorCode: json["code"] as? Int,
            message: json["message"] as? String
        )
    }

    /// Serializes the error to a JSON map.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        ["rpcErrorCode": rpcErrorCode as Any, "message": message as Any]
    }
}

/// Task container returned by the A2A API.
/// Includes identifiers plus an optional status payload.
public struct A2ATask: A2AResult {
    public var id: String
    public var contextId: String?
    public var status: A2ATaskStatus?

    /// Creates a task with optional context and status.
    /// Use this when constructing task results manually.
    public init(id: String, contextId: String? = nil, status: A2ATaskStatus? = nil) {
        self.id = id
        self.contextId = contextId
        self.status = status
    }

    /// Parses a task payload from a JSON map.
    /// Reads the id plus optional status and context.
    public static func fromJson(_ json: JsonMap) -> A2ATask {
        let statusJson = json["status"] as? JsonMap
        return A2ATask(
            id: json["id"] as? String ?? "",
            contextId: json["contextId"] as? String,
            status: statusJson.map { A2ATaskStatus.fromJson($0) }
        )
    }

    /// Serializes the task to a JSON map.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        var json: JsonMap = ["id": id]
        if let contextId {
            json["contextId"] = contextId
        }
        if let status {
            json["status"] = status.toJson()
        }
        return json
    }
}

/// Latest status snapshot for a task.
/// Holds the most recent message payload, if available.
public struct A2ATaskStatus {
    public var message: A2AMessage?

    /// Creates a status payload with an optional message.
    /// Use nil when no message is available.
    public init(message: A2AMessage? = nil) {
        self.message = message
    }

    /// Parses task status from a JSON map.
    /// Reads the embedded message payload if present.
    public static func fromJson(_ json: JsonMap) -> A2ATaskStatus {
        let messageJson = json["message"] as? JsonMap
        return A2ATaskStatus(message: messageJson.map { A2AMessage.fromJson($0) })
    }

    /// Serializes the status to a JSON map.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        ["message": message?.toJson() as Any]
    }
}

/// Streaming event that reports task progress.
/// Carries identifiers, status payload, and an optional end flag.
public struct A2ATaskStatusUpdateEvent: A2AResult {
    public var taskId: String?
    public var contextId: String?
    public var status: A2ATaskStatus?
    public var end: Bool?

    /// Creates a status update event with optional fields.
    /// Use nil to omit identifiers or status data.
    public init(
        taskId: String? = nil,
        contextId: String? = nil,
        status: A2ATaskStatus? = nil,
        end: Bool? = nil
    ) {
        self.taskId = taskId
        self.contextId = contextId
        self.status = status
        self.end = end
    }

    /// Parses a status update from a JSON map.
    /// Reads identifiers, nested status, and end flag.
    public static func fromJson(_ json: JsonMap) -> A2ATaskStatusUpdateEvent {
        let statusJson = json["status"] as? JsonMap
        return A2ATaskStatusUpdateEvent(
            taskId: json["taskId"] as? String,
            contextId: json["contextId"] as? String,
            status: statusJson.map { A2ATaskStatus.fromJson($0) },
            end: json["end"] as? Bool
        )
    }

    /// Serializes the update to a JSON map.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        var json: JsonMap = [:]
        if let taskId { json["taskId"] = taskId }
        if let contextId { json["contextId"] = contextId }
        if let status { json["status"] = status.toJson() }
        if let end { json["end"] = end }
        return json
    }
}

/// Errors thrown by A2A client implementations.
/// Covers validation, HTTP, and parsing failures.
public enum A2AClientError: Error {
    case invalidAgentCard
    case streamingNotSupported
    case invalidResponse
    case invalidContentType
    case responseIdMismatch
}

/// URLSession-based A2A client implementation.
/// Handles agent-card discovery, JSON-RPC requests, and SSE streaming.
public final class A2AClient: A2AClientProtocol {
    public let agentBaseUrl: String
    public let agentCardPath: String
    public var customHeaders: [String: String]
    public var authenticationHandler: A2AAuthenticationHandler?

    private var serviceEndpointUrl: String?
    private var agentCard: A2AAgentCard?
    private var requestIdCounter: Int = 1
    private let session: URLSession

    /// Creates a client for the given agent base URL.
    /// Optionally prefetches the agent card in the background.
    public init(
        baseUrl: String,
        cardPath: String = "/.well-known/agent-card.json",
        customHeaders: [String: String] = [:],
        authenticationHandler: A2AAuthenticationHandler? = nil,
        agentCardBackgroundFetch: Bool = true,
        session: URLSession = .shared
    ) {
        self.agentBaseUrl = baseUrl.replacingOccurrences(of: "/$", with: "", options: .regularExpression)
        self.agentCardPath = cardPath
        self.customHeaders = customHeaders
        self.authenticationHandler = authenticationHandler
        self.serviceEndpointUrl = self.agentBaseUrl
        self.session = session

        if agentCardBackgroundFetch {
            Task {
                _ = try? await fetchAndCacheAgentCard(baseUrl: nil, cardPath: nil)
            }
        }
    }

    /// Fetches and caches the agent card.
    /// Updates the service endpoint URL when available.
    public func getAgentCard() async throws -> A2AAgentCard {
        try await fetchAndCacheAgentCard(baseUrl: nil, cardPath: nil)
    }

    /// Sends a `message/send` request to the agent.
    /// Throws if the response is invalid or indicates failure.
    public func sendMessage(_ payload: A2AMessageSendParams) async throws {
        _ = try await postRpcRequest(method: "message/send", params: payload)
    }

    /// Sends a `message/stream` request and returns an SSE stream.
    /// Throws if streaming is unsupported or the SSE payload is invalid.
    public func sendMessageStream(_ payload: A2AMessageSendParams) -> AsyncThrowingStream<A2ASendStreamMessageResponse, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let endpoint = try await serviceEndpoint()
                    let requestId = nextRequestId()
                    let rpcRequest = A2AJsonRpcRequest(
                        method: "message/stream",
                        id: requestId,
                        params: payload.toJson()
                    )

                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    var headers = customHeaders
                    if let authHeaders = await authenticationHandler?.headers {
                        headers.merge(authHeaders) { _, new in new }
                    }
                    if !payload.extensions.isEmpty {
                        headers["X-A2A-Extensions"] = payload.extensions.joined(separator: ",")
                    }
                    for (key, value) in headers {
                        request.setValue(value, forHTTPHeaderField: key)
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: rpcRequest.toJson())

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw A2AClientError.invalidResponse
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw A2AClientError.invalidResponse
                    }
                    guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
                          contentType.starts(with: "text/event-stream") else {
                        throw A2AClientError.invalidContentType
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payloadString = String(line.dropFirst(6))
                        guard let data = payloadString.data(using: .utf8),
                              let json = try JSONSerialization.jsonObject(with: data) as? JsonMap else {
                            continue
                        }
                        let response = try parseStreamResponse(json, requestId: requestId)
                        continuation.yield(response)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func serviceEndpoint() async throws -> URL {
        if let serviceEndpointUrl, let url = URL(string: serviceEndpointUrl) {
            return url
        }
        let card = try await fetchAndCacheAgentCard(baseUrl: nil, cardPath: nil)
        guard let url = URL(string: card.url) else {
            throw A2AClientError.invalidAgentCard
        }
        return url
    }

    private func nextRequestId() -> Int {
        defer { requestIdCounter += 1 }
        return requestIdCounter
    }

    private func fetchAndCacheAgentCard(baseUrl: String?, cardPath: String?) async throws -> A2AAgentCard {
        let base = (baseUrl?.isEmpty == false) ? baseUrl! : agentBaseUrl
        let path = (cardPath?.isEmpty == false) ? cardPath! : agentCardPath
        let urlString = "\(base)\(path)"
        guard let url = URL(string: urlString) else {
            throw A2AClientError.invalidAgentCard
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var headers = customHeaders
        if let authHeaders = await authenticationHandler?.headers {
            headers.merge(authHeaders) { _, new in new }
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw A2AClientError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? JsonMap else {
            throw A2AClientError.invalidAgentCard
        }
        let card = try A2AAgentCard.fromJson(json)
        serviceEndpointUrl = card.url
        agentCard = card
        return card
    }

    private func postRpcRequest(method: String, params: A2AMessageSendParams) async throws -> JsonMap {
        let endpoint = try await serviceEndpoint()
        let requestId = nextRequestId()
        let rpcRequest = A2AJsonRpcRequest(method: method, id: requestId, params: params.toJson())

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var headers = customHeaders
        if let authHeaders = await authenticationHandler?.headers {
            headers.merge(authHeaders) { _, new in new }
        }
        if !params.extensions.isEmpty {
            headers["X-A2A-Extensions"] = params.extensions.joined(separator: ",")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: rpcRequest.toJson())

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw A2AClientError.invalidResponse
        }

        if let authHandler = authenticationHandler,
           let retryHeaders = await authHandler.shouldRetryWithHeaders(request: request, response: httpResponse, body: data) {
            var retryRequest = request
            for (key, value) in retryHeaders {
                retryRequest.setValue(value, forHTTPHeaderField: key)
            }
            let (retryData, retryResponse) = try await session.data(for: retryRequest)
            guard let retryHttp = retryResponse as? HTTPURLResponse,
                  (200..<300).contains(retryHttp.statusCode) else {
                throw A2AClientError.invalidResponse
            }
            await authHandler.onSuccessfulRetry(retryHeaders)
            guard let retryJson = try JSONSerialization.jsonObject(with: retryData) as? JsonMap else {
                throw A2AClientError.invalidResponse
            }
            return retryJson
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw A2AClientError.invalidResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? JsonMap else {
            throw A2AClientError.invalidResponse
        }
        return json
    }

    private func parseStreamResponse(_ json: JsonMap, requestId: Int) throws -> A2ASendStreamMessageResponse {
        if let id = json["id"] as? Int, id != requestId {
            throw A2AClientError.responseIdMismatch
        }
        if let errorJson = json["error"] as? JsonMap {
            return A2AJSONRPCErrorResponseSSM(error: A2AError.fromJson(errorJson), id: json["id"] as? Int)
        }
        let resultJson = json["result"] as? JsonMap
        let result = resultJson.flatMap { parseResult($0) }
        return A2ASendStreamMessageSuccessResponse(result: result, id: json["id"] as? Int)
    }

    private func parseResult(_ json: JsonMap) -> A2AResult? {
        if json["messageId"] != nil {
            return A2AMessage.fromJson(json)
        }
        if json["id"] != nil && json["status"] != nil {
            return A2ATask.fromJson(json)
        }
        if json["status"] != nil && (json["taskId"] != nil || json["end"] != nil) {
            return A2ATaskStatusUpdateEvent.fromJson(json)
        }
        return nil
    }
}
