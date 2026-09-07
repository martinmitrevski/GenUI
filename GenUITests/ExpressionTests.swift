//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
import Testing
@testable import GenUI

@Suite("Expression evaluation")
struct ExpressionEvaluatorTests {
    @Test("Literals, bindings and calls all evaluate")
    func basics() {
        let (evaluator, model) = makeEvaluator(data: ["name": "Ada", "count": 3])
        let context = DataContext(model, "/")

        #expect(Json.string(evaluator.evaluate(DynamicValue("hi"), in: context)) == "hi")
        #expect(Json.string(evaluator.evaluate(DynamicValue(["path": "/name"]), in: context)) == "Ada")
        #expect(evaluator.evaluate(.missing, in: context) == nil)
        #expect(Json.int(evaluator.evaluate(DynamicValue(["path": "/count"]), in: context)) == 3)
        #expect(evaluator.evaluate(DynamicValue(["path": "/missing"]), in: context) == nil)
    }

    @Test("Coercing accessors follow the type conversion rules")
    func coercion() {
        let (evaluator, model) = makeEvaluator(data: ["count": 3, "flag": true, "tags": ["a", "b"]])
        let context = DataContext(model, "/")

        #expect(evaluator.string(DynamicValue(["path": "/count"]), in: context) == "3")
        #expect(evaluator.double(DynamicValue(["path": "/count"]), in: context) == 3)
        #expect(evaluator.bool(DynamicValue(["path": "/flag"]), in: context) == true)
        #expect(evaluator.stringArray(DynamicValue(["path": "/tags"]), in: context) == ["a", "b"])
    }

    @Test("Relative bindings resolve inside a collection scope")
    func relativeBindings() {
        let (evaluator, model) = makeEvaluator(data: ["items": [["name": "Tea"], ["name": "Coffee"]]])
        let scope = DataContext(model, "/").collectionScope(path: DataPath("/items"), index: 1)

        #expect(evaluator.string(DynamicValue(["path": "name"]), in: scope) == "Coffee")
    }

    @Test("Nested call arguments are resolved before the function runs")
    func nestedArguments() {
        let (evaluator, model) = makeEvaluator(data: ["a": 2])
        let context = DataContext(model, "/")
        let call = FunctionCall(
            name: "echo",
            arguments: ["value": ["call": "echo", "args": ["value": ["path": "/a"]]]]
        )

        #expect(Json.int(evaluator.invoke(call, in: context)) == 2)
    }

    @Test("Arrays of calls are resolved element by element")
    func arrayArguments() {
        let (evaluator, model) = makeEvaluator(data: ["a": true, "b": false])
        let context = DataContext(model, "/")
        let call = FunctionCall(
            name: "and",
            arguments: ["values": [["path": "/a"], ["path": "/b"]]]
        )

        #expect(Json.bool(evaluator.invoke(call, in: context)) == false)
    }

    @Test("Unknown functions are routed to the agent")
    func agentRouting() {
        let router = StubRemoteRouter()
        router.answers["deliveryEstimate"] = "25 min"
        let (evaluator, model) = makeEvaluator(data: ["type": "pickup"], router: router)
        let context = DataContext(model, "/")
        let call = FunctionCall(name: "deliveryEstimate", arguments: ["orderType": ["path": "/type"]])

        #expect(Json.string(evaluator.invoke(call, in: context)) == "25 min")
        #expect(router.calls.count == 1)
        #expect(router.calls[0].name == "deliveryEstimate")
        #expect(Json.string(router.calls[0].arguments["orderType"]) == "pickup")
    }

    @Test("Agent-only functions cannot be bound to component properties")
    func callBoundary() {
        let router = StubRemoteRouter()
        let (evaluator, model) = makeEvaluator(router: router)
        let context = DataContext(model, "/")

        #expect(evaluator.invoke(FunctionCall(name: "agentOnly"), in: context) == nil)
        #expect(router.errors.count == 1)
        #expect(router.errors[0].code == RendererError.Code.invalidFunctionCall)
    }

    @Test("A failing function reports an error and evaluates to nil")
    func functionFailure() {
        let router = StubRemoteRouter()
        let (evaluator, model) = makeEvaluator(router: router)
        let context = DataContext(model, "/")

        #expect(evaluator.invoke(FunctionCall(name: "boom"), in: context) == nil)
        #expect(router.errors.count == 1)
        #expect(router.errors[0].code == RendererError.Code.executionFailed)
    }

    @Test("Functions resolve through the surface catalog, not any catalog")
    func catalogResolution() {
        let router = StubRemoteRouter()
        let (evaluator, model) = makeEvaluator(surfaceCatalogId: "unknown:catalog", router: router)
        let context = DataContext(model, "/")

        // With an unresolvable surface catalog the call is not local, so it is
        // routed to the agent rather than silently resolved elsewhere.
        _ = evaluator.invoke(FunctionCall(name: "echo", arguments: ["value": 1]), in: context)
        #expect(router.calls.count == 1)
    }

    @Test("The @index system function reads the collection scope")
    func indexFunction() {
        let (evaluator, model) = makeEvaluator(data: ["items": [1, 2, 3]])
        let scope = DataContext(model, "/").collectionScope(path: DataPath("/items"), index: 1)
        let rootScope = DataContext(model, "/")

        #expect(Json.int(evaluator.invoke(FunctionCall(name: "@index"), in: scope)) == 1)
        #expect(
            Json.int(evaluator.invoke(FunctionCall(name: "@index", arguments: ["offset": 1]), in: scope)) == 2
        )
        #expect(evaluator.invoke(FunctionCall(name: "@index"), in: rootScope) == nil)
    }

    @Test("Failing checks carry the rule's fallback message")
    func checks() {
        let (evaluator, model) = makeEvaluator(data: ["form": ["email": ""] as JsonMap])
        let context = DataContext(model, "/")
        let rules = CheckRule.list(
            [
                [
                    "condition": ["call": "required", "args": ["value": ["path": "/form/email"]]],
                    "message": "We need your email."
                ],
                ["condition": ["call": "required", "args": ["value": "present"]]]
            ]
        )

        let failures = evaluator.failingChecks(rules, in: context)
        #expect(failures.count == 1)
        #expect(failures[0].message == "We need your email.")
    }

    @Test("Boolean conditions are accepted as checks")
    func booleanChecks() {
        let (evaluator, model) = makeEvaluator(data: ["ok": false])
        let context = DataContext(model, "/")
        let rules = CheckRule.list([["condition": ["path": "/ok"], "message": "Not ok."]])

        #expect(evaluator.failingChecks(rules, in: context).count == 1)
    }
}

@Suite("formatString parsing")
struct ExpressionParserTests {
    @Test("Templates split into text and expressions")
    func templates() {
        let segments = A2uiExpressionParser.parseTemplate("Hello ${/user/name}, welcome!")

        #expect(segments.count == 3)
        #expect(segments[0] == .text("Hello "))
        #expect(segments[1] == .expression(.path(DataPath("/user/name"))))
        #expect(segments[2] == .text(", welcome!"))
    }

    @Test("A literal dollar-brace sequence can be escaped")
    func escaping() {
        let segments = A2uiExpressionParser.parseTemplate("Cost: \\${/price}")
        #expect(segments == [.text("Cost: ${/price}")])
    }

    @Test("Function calls parse their named arguments")
    func functionCalls() {
        let expression = A2uiExpressionParser.parseExpression("formatDate(value:${/date}, format:'MMM d')")

        guard case let .call(name, arguments) = expression else {
            Issue.record("Expected a call expression, got \(String(describing: expression))")
            return
        }
        #expect(name == "formatDate")
        #expect(arguments["value"] == .path(DataPath("/date")))
        #expect(arguments["format"] == .literal("MMM d"))
    }

    @Test("Calls without arguments and nested calls parse")
    func nestedCalls() {
        #expect(A2uiExpressionParser.parseExpression("now()") == .call(name: "now", arguments: [:]))

        let expression = A2uiExpressionParser.parseExpression("upper(value: ${lower(value: 'A')})")
        guard case let .call(_, arguments) = expression,
              case let .call(inner, innerArguments)? = arguments["value"] else {
            Issue.record("Expected a nested call")
            return
        }
        #expect(inner == "lower")
        #expect(innerArguments["value"] == .literal("A"))
    }

    @Test("System functions and numeric arguments parse")
    func systemFunctions() {
        let expression = A2uiExpressionParser.parseExpression("@index(offset: 1)")
        #expect(expression == .call(name: "@index", arguments: ["offset": .literal(1.0)]))
    }

    @Test("Unterminated expressions stay literal text")
    func unterminated() {
        #expect(A2uiExpressionParser.parseTemplate("broken ${/a") == [.text("broken ${/a")])
    }

    @Test("Braces inside quoted arguments do not end the expression")
    func quotedBraces() {
        let segments = A2uiExpressionParser.parseTemplate("${formatDate(value: '}', format: 'y')}")
        #expect(segments.count == 1)
        if case let .expression(.call(name, _)) = segments[0] {
            #expect(name == "formatDate")
        } else {
            Issue.record("Expected a call expression")
        }
    }
}

@Suite("formatString evaluation")
struct InterpolationTests {
    @Test("Paths, functions and literals interpolate")
    func interpolation() {
        let (evaluator, model) = makeEvaluator(
            data: ["user": ["name": "Ada"] as JsonMap, "appName": "GenUI", "count": 2]
        )
        let context = DataContext(model, "/")

        #expect(
            evaluator.interpolate("Hello, ${/user/name}! Welcome to ${/appName}.", in: context)
                == "Hello, Ada! Welcome to GenUI."
        )
        #expect(evaluator.interpolate("Total: ${/count}", in: context) == "Total: 2")
    }

    @Test("Missing values interpolate as empty strings")
    func missingValues() {
        let (evaluator, model) = makeEvaluator()
        #expect(evaluator.interpolate("[${/nope}]", in: DataContext(model, "/")) == "[]")
    }

    @Test("Relative paths interpolate inside a collection scope")
    func relativePaths() {
        let (evaluator, model) = makeEvaluator(data: ["items": [["name": "Tea", "quantity": 2]]])
        let scope = DataContext(model, "/").collectionScope(path: DataPath("/items"), index: 0)

        #expect(evaluator.interpolate("${name} x${quantity}", in: scope) == "Tea x2")
        #expect(evaluator.interpolate("#${@index(offset: 1)}", in: scope) == "#1")
    }

    @Test("Nested function calls interpolate")
    func nestedCalls() {
        let (evaluator, model) = makeEvaluator(data: ["price": 12.5])
        let context = DataContext(model, "/")

        #expect(
            evaluator.interpolate("${formatCurrency(value: ${/price}, currency: 'USD')}", in: context)
                == "$12.50"
        )
    }

    @Test("Objects interpolate as JSON")
    func objectInterpolation() {
        let (evaluator, model) = makeEvaluator(data: ["point": ["x": 1] as JsonMap])
        #expect(evaluator.interpolate("${/point}", in: DataContext(model, "/")) == "{\"x\":1}")
    }
}
