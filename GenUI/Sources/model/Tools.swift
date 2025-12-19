//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

public let surfaceIdKey = "surfaceId"

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

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(name: String, description: String, parameters: Schema? = nil, prefix: String? = nil) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.prefix = prefix
    }

    open func invoke(_ args: JsonMap) async -> T {
        fatalError("Subclasses must implement invoke")
    }
}

public final class DynamicAiTool<T>: AiTool<T> {
    /// Async closure used by DynamicAiTool.
    /// Receives tool arguments and returns the tool result.
    public typealias InvokeFunction = (JsonMap) async -> T

    private let invokeFunction: InvokeFunction

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
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

    public override func invoke(_ args: JsonMap) async -> T {
        await invokeFunction(args)
    }
}
