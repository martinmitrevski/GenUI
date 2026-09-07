//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Routes function calls that the renderer cannot execute locally.
///
/// A2UI v1.0 defines implicit fallback routing: when a function referenced by a
/// component tree is not registered locally, the renderer sends a
/// `callAgentFunction` message and renders a pending state until the agent
/// answers.
public protocol RemoteFunctionRouter: AnyObject {
    /// Returns the agent's answer for a call, dispatching it when needed.
    ///
    /// Implementations return `nil` while the call is in flight, and the
    /// resolved value once the matching `agentFunctionResponse` has arrived.
    func agentFunctionValue(
        for name: String,
        catalogId: String?,
        arguments: [String: Any],
        surfaceId: String
    ) -> Any?

    /// Reports a renderer-side error to the agent.
    /// Used for call boundary violations and failed evaluations.
    func report(_ error: RendererError)
}

/// Evaluates A2UI dynamic values, function calls and validation checks.
///
/// One evaluator is created per surface, because function resolution depends on
/// the surface's default catalog. Evaluation is synchronous: local functions run
/// immediately, while agent-routed functions return `nil` until their result
/// arrives.
public final class ExpressionEvaluator {
    /// The catalogs available for function resolution.
    public let catalogs: CatalogRegistry

    /// The surface this evaluator belongs to.
    public let surfaceId: String

    /// The default catalog id of the surface.
    public let surfaceCatalogId: String?

    /// Host capabilities passed to function implementations.
    public let services: RendererServices

    /// Receives calls that cannot be resolved locally.
    public weak var remoteRouter: RemoteFunctionRouter?

    /// Creates an evaluator for one surface.
    /// Pass the surface's default catalog id so unqualified calls resolve.
    public init(
        catalogs: CatalogRegistry,
        surfaceId: String,
        surfaceCatalogId: String?,
        services: RendererServices = .default,
        remoteRouter: RemoteFunctionRouter? = nil
    ) {
        self.catalogs = catalogs
        self.surfaceId = surfaceId
        self.surfaceCatalogId = surfaceCatalogId
        self.services = services
        self.remoteRouter = remoteRouter
    }

    // MARK: - Dynamic values

    /// Evaluates a dynamic value in the given scope.
    /// Returns `nil` for missing properties and unresolved values.
    public func evaluate(_ value: DynamicValue, in context: DataContext) -> Any? {
        switch value {
        case .missing:
            return nil
        case let .literal(literal):
            return Json.normalized(literal)
        case let .binding(path):
            return context.value(at: path)
        case let .function(call):
            return invoke(call, in: context)
        }
    }

    /// Evaluates a raw wire value in the given scope.
    /// Nested arrays and objects are resolved recursively.
    public func evaluateRaw(_ raw: Any?, in context: DataContext) -> Any? {
        guard let raw = Json.normalized(raw) else { return nil }

        if let map = raw as? JsonMap {
            if let call = FunctionCall(map) {
                return invoke(call, in: context)
            }
            if map.count == 1, let path = map["path"] as? String {
                return context.value(at: DataPath(path))
            }
            return map.compactMapValues { evaluateRaw($0, in: context) }
        }
        if let array = raw as? JsonArray {
            return array.map { evaluateRaw($0, in: context) ?? NSNull() }
        }
        return raw
    }

    /// Evaluates a dynamic value and coerces it to a string.
    /// Coercion follows the A2UI type conversion rules.
    public func string(_ value: DynamicValue, in context: DataContext) -> String? {
        Json.string(evaluate(value, in: context))
    }

    /// Evaluates a dynamic value and coerces it to a number.
    public func double(_ value: DynamicValue, in context: DataContext) -> Double? {
        Json.double(evaluate(value, in: context))
    }

    /// Evaluates a dynamic value and coerces it to a boolean.
    public func bool(_ value: DynamicValue, in context: DataContext) -> Bool? {
        Json.bool(evaluate(value, in: context))
    }

    /// Evaluates a dynamic value and coerces it to a list of strings.
    public func stringArray(_ value: DynamicValue, in context: DataContext) -> [String]? {
        Json.stringArray(evaluate(value, in: context))
    }

    // MARK: - Function calls

    /// Evaluates a function call in the given scope.
    /// Arguments are resolved before the function runs.
    public func invoke(_ call: FunctionCall, in context: DataContext) -> Any? {
        let arguments = resolveArguments(call.arguments, in: context)
        return invoke(
            name: call.name,
            catalogId: call.catalogId,
            resolvedArguments: arguments,
            in: context
        )
    }

    /// Evaluates a function by name with already-resolved arguments.
    ///
    /// System functions are handled first, then the surface catalogs, and
    /// finally the agent through ``RemoteFunctionRouter``.
    public func invoke(
        name: String,
        catalogId: String?,
        resolvedArguments: [String: Any],
        in context: DataContext
    ) -> Any? {
        if name.hasPrefix(A2uiProtocol.systemFunctionPrefix) {
            return invokeSystemFunction(name: name, arguments: resolvedArguments, in: context)
        }

        let call = FunctionCall(name: name, catalogId: catalogId)
        if let definition = catalogs.function(call, surfaceCatalogId: surfaceCatalogId) {
            guard definition.isRendererCallable else {
                let error = RendererError(
                    code: RendererError.Code.invalidFunctionCall,
                    message: "Function '\(name)' is agentOnly and cannot be bound to component properties.",
                    surfaceId: surfaceId
                )
                genUiLogger.severe(error.message)
                remoteRouter?.report(error)
                return nil
            }
            return execute(definition, arguments: resolvedArguments, in: context)
        }

        guard let remoteRouter else {
            genUiLogger.severe("Function '\(name)' is not registered and no agent route is available.")
            return nil
        }
        return remoteRouter.agentFunctionValue(
            for: name,
            catalogId: catalogId,
            arguments: resolvedArguments,
            surfaceId: surfaceId
        )
    }

    /// Executes a function definition, reporting failures to the agent.
    /// Returns `nil` when the implementation throws.
    public func execute(
        _ definition: FunctionDefinition,
        arguments: [String: Any],
        in context: DataContext
    ) -> Any? {
        do {
            return try definition.implementation(
                FunctionInvocation(
                    name: definition.name,
                    arguments: arguments,
                    context: context,
                    services: services,
                    evaluator: self
                )
            )
        } catch {
            let message = A2uiErrorFormatter.describe(error)
            let code = (error as? A2uiFunctionError)?.code ?? RendererError.Code.executionFailed
            genUiLogger.severe("Function '\(definition.name)' failed: \(message)")
            remoteRouter?.report(
                RendererError(code: code, message: message, surfaceId: surfaceId)
            )
            return nil
        }
    }

    /// Resolves the raw arguments of a call in the given scope.
    /// Nested bindings and calls are evaluated depth first.
    public func resolveArguments(_ arguments: JsonMap, in context: DataContext) -> [String: Any] {
        var resolved: [String: Any] = [:]
        for (key, value) in arguments {
            if let evaluated = evaluateRaw(value, in: context) {
                resolved[key] = evaluated
            }
        }
        return resolved
    }

    // MARK: - Interpolation

    /// Interpolates a `formatString` template in the given scope.
    /// Unresolved expressions become empty strings.
    public func interpolate(_ template: String, in context: DataContext) -> String {
        var output = ""
        for segment in A2uiExpressionParser.parseTemplate(template) {
            switch segment {
            case let .text(text):
                output += text
            case let .expression(expression):
                output += Json.stringify(evaluate(expression, in: context))
            }
        }
        return output
    }

    /// Evaluates a parsed template expression.
    /// Calls are dispatched through the regular function resolution path.
    public func evaluate(_ expression: A2uiExpression, in context: DataContext) -> Any? {
        switch expression {
        case let .literal(value):
            return Json.normalized(value)
        case let .path(path):
            return context.value(at: path)
        case let .call(name, arguments):
            var resolved: [String: Any] = [:]
            for (key, argument) in arguments {
                if let value = evaluate(argument, in: context) {
                    resolved[key] = value
                }
            }
            return invoke(name: name, catalogId: nil, resolvedArguments: resolved, in: context)
        }
    }

    // MARK: - Validation

    /// Evaluates the failing checks of a component.
    ///
    /// Conditions that evaluate to a boolean are coerced into a validation
    /// result, and unresolved conditions are treated as passing so streaming
    /// UIs are not disabled while data is still arriving.
    ///
    /// A message written on the check wins over the one the validation
    /// function produced: the catalog instructions tell agents to put custom
    /// error messages on the check, so that message is the more specific one.
    public func failingChecks(_ checks: [CheckRule], in context: DataContext) -> [ValidationResult] {
        checks.compactMap { rule in
            let result = ValidationResult(coercing: evaluate(rule.condition, in: context))
            guard !result.isValid else { return nil }
            guard let message = rule.message else { return result }
            return ValidationResult(
                isValid: false,
                code: result.code,
                message: message,
                severity: result.severity
            )
        }
    }

    // MARK: - System functions

    private func invokeSystemFunction(
        name: String,
        arguments: [String: Any],
        in context: DataContext
    ) -> Any? {
        switch name {
        case "@index":
            guard let index = context.itemIndex else {
                genUiLogger.severe("'@index' was used outside of a list template scope.")
                return nil
            }
            let offset = Json.int(arguments["offset"]) ?? 0
            return index + offset
        default:
            genUiLogger.severe("Unknown system function '\(name)'.")
            return nil
        }
    }
}
