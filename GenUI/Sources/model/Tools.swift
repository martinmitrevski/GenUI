//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

public let surfaceIdKey = "surfaceId"

/// Base class for AI tool definitions.
/// Subclasses implement `invoke` to perform the tool's work.
open class AiTool<T> {
    public let name: String
    public let description: String
    public let parameters: Schema?
    public let prefix: String?

    public var fullName: String {
        if let prefix {
            return "\(prefix).\(name)"
        }
        return name
    }

    /// Creates a tool definition.
    /// Provide name, description, and optional parameter schema.
    public init(name: String, description: String, parameters: Schema? = nil, prefix: String? = nil) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.prefix = prefix
    }

    /// Invokes the tool with the provided arguments.
    /// Subclasses must override this method.
    open func invoke(_ args: JsonMap) async -> T {
        fatalError("Subclasses must implement invoke")
    }
}

/// Dynamic tool backed by an async closure.
/// Use this for lightweight tool implementations.
public final class DynamicAiTool<T>: AiTool<T> {
    /// Async closure used by `DynamicAiTool`.
    /// Receives tool arguments and returns the tool result.
    public typealias InvokeFunction = (JsonMap) async -> T

    private let invokeFunction: InvokeFunction

    /// Creates a tool backed by a custom invoke closure.
    /// Provide a name, description, and invoke implementation.
    public init(
        name: String,
        description: String,
        parameters: Schema? = nil,
        invokeFunction: @escaping InvokeFunction,
        prefix: String? = nil
    ) {
        self.invokeFunction = invokeFunction
        super.init(name: name, description: description, parameters: parameters, prefix: prefix)
    }

    /// Invokes the wrapped closure with the provided arguments.
    /// Returns the closure result.
    public override func invoke(_ args: JsonMap) async -> T {
        await invokeFunction(args)
    }
}
