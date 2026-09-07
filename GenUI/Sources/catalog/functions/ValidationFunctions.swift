//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// The validation functions of the A2UI basic catalog.
///
/// Every function returns a ``ValidationResult`` payload so that components can
/// show a message and, in the case of `Button`, disable themselves.
public enum ValidationFunctions {
    /// All validation functions, in catalog order.
    public static var all: [FunctionDefinition] {
        [required, regex, length, numeric, email]
    }

    /// Checks that a value is present and not empty.
    public static let required = FunctionDefinition(
        name: "required",
        description: "Checks that the value is not null, undefined, or empty.",
        arguments: JsonSchema.object(
            properties: ["value": ["description": "The value to check."]],
            required: ["value"],
            additionalProperties: false
        ),
        returnType: .validationResult
    ) { invocation in
        let value = invocation.value("value")
        let isPresent: Bool
        switch value {
        case nil:
            isPresent = false
        case let string as String:
            isPresent = !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let array as JsonArray:
            isPresent = !array.isEmpty
        case let map as JsonMap:
            isPresent = !map.isEmpty
        default:
            isPresent = true
        }
        return isPresent
            ? ValidationResult.valid.rawValue
            : ValidationResult.invalid("This field is required.", code: "REQUIRED").rawValue
    }

    /// Checks that a value matches a regular expression.
    ///
    /// Empty values pass so that optional fields do not report an error before
    /// the user has typed anything; combine with `required` to make a field
    /// mandatory.
    public static let regex = FunctionDefinition(
        name: "regex",
        description: "Checks that the value matches a regular expression string.",
        arguments: JsonSchema.object(
            properties: [
                "value": JsonSchema.dynamicString(),
                "pattern": JsonSchema.string(description: "The regex pattern to match against.")
            ],
            required: ["value", "pattern"],
            additionalProperties: false
        ),
        returnType: .validationResult
    ) { invocation in
        let pattern = try invocation.requireString("pattern")
        let value = invocation.string("value") ?? ""
        guard !value.isEmpty else { return ValidationResult.valid.rawValue }

        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            throw A2uiFunctionError.invalidArgument(
                "pattern",
                function: "regex",
                reason: "'\(pattern)' is not a valid regular expression."
            )
        }
        let range = NSRange(value.startIndex..., in: value)
        let matches = expression.firstMatch(in: value, options: [], range: range) != nil
        return matches
            ? ValidationResult.valid.rawValue
            : ValidationResult.invalid("This value has an invalid format.", code: "PATTERN_MISMATCH").rawValue
    }

    /// Checks the length of a string against `min` and `max` bounds.
    public static let length = FunctionDefinition(
        name: "length",
        description: "Checks string length constraints.",
        arguments: JsonSchema.object(
            properties: [
                "value": JsonSchema.dynamicString(),
                "min": JsonSchema.integer(description: "The minimum allowed length.", minimum: 0),
                "max": JsonSchema.integer(description: "The maximum allowed length.", minimum: 0)
            ],
            required: ["value"],
            additionalProperties: false
        ),
        returnType: .validationResult
    ) { invocation in
        let value = invocation.string("value") ?? ""
        if let min = invocation.int("min"), value.count < min {
            return ValidationResult.invalid(
                "Enter at least \(min) character\(min == 1 ? "" : "s").",
                code: "TOO_SHORT"
            ).rawValue
        }
        if let max = invocation.int("max"), value.count > max {
            return ValidationResult.invalid(
                "Enter at most \(max) character\(max == 1 ? "" : "s").",
                code: "TOO_LONG"
            ).rawValue
        }
        return ValidationResult.valid.rawValue
    }

    /// Checks that a number is within the `min` and `max` bounds.
    public static let numeric = FunctionDefinition(
        name: "numeric",
        description: "Checks numeric range constraints.",
        arguments: JsonSchema.object(
            properties: [
                "value": JsonSchema.dynamicNumber(),
                "min": JsonSchema.number(description: "The minimum allowed value."),
                "max": JsonSchema.number(description: "The maximum allowed value.")
            ],
            required: ["value"],
            additionalProperties: false
        ),
        returnType: .validationResult
    ) { invocation in
        guard let rawValue = invocation.value("value"), !Json.isNull(rawValue) else {
            return ValidationResult.valid.rawValue
        }
        guard let value = Json.double(rawValue) else {
            return ValidationResult.invalid("Enter a number.", code: "NOT_A_NUMBER").rawValue
        }
        if let min = invocation.double("min"), value < min {
            return ValidationResult.invalid(
                "Enter a value of at least \(Json.stringify(min)).",
                code: "OUT_OF_RANGE"
            ).rawValue
        }
        if let max = invocation.double("max"), value > max {
            return ValidationResult.invalid(
                "Enter a value of at most \(Json.stringify(max)).",
                code: "OUT_OF_RANGE"
            ).rawValue
        }
        return ValidationResult.valid.rawValue
    }

    /// Checks that a value is a syntactically valid email address.
    public static let email = FunctionDefinition(
        name: "email",
        description: "Checks that the value is a valid email address.",
        arguments: JsonSchema.object(
            properties: ["value": JsonSchema.dynamicString()],
            required: ["value"],
            additionalProperties: false
        ),
        returnType: .validationResult
    ) { invocation in
        let value = invocation.string("value") ?? ""
        guard !value.isEmpty else { return ValidationResult.valid.rawValue }
        return isValidEmail(value)
            ? ValidationResult.valid.rawValue
            : ValidationResult.invalid("Enter a valid email address.", code: "INVALID_EMAIL").rawValue
    }

    /// Validates an email address with a conservative pattern.
    /// Exposed for reuse by app-specific catalogs.
    public static func isValidEmail(_ value: String) -> Bool {
        let pattern = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(value.startIndex..., in: value)
        return expression.firstMatch(in: value, options: [], range: range) != nil
    }
}
