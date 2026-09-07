//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// The formatting functions of the A2UI basic catalog.
///
/// A2UI has no operators, so agents use these functions for string
/// interpolation, number, currency and date formatting.
public enum FormatFunctions {
    /// All formatting functions, in catalog order.
    public static var all: [FunctionDefinition] {
        [formatString, formatNumber, formatCurrency, formatDate, pluralize]
    }

    /// Interpolates data model values and function results into a string.
    ///
    /// The template supports `${/absolute/path}`, `${relative/path}` and
    /// `${functionName(arg: value)}` expressions, and `\${` for a literal.
    public static let formatString = FunctionDefinition(
        name: "formatString",
        description: """
        Performs string interpolation of data model values and other functions in the catalog functions list \
        and returns the resulting string. The value string can contain interpolated expressions in the \
        `${expression}` format. Supported expression types include: JSON Pointer paths to the data model \
        (e.g., `${/absolute/path}` or `${relative/path}`), and renderer-side function calls (e.g., `${now()}`). \
        Function arguments must be named (e.g., `${formatDate(value:${/currentDate}, format:'MM-dd')}`). \
        To include a literal `${` sequence, escape it as `\\${`.
        """,
        arguments: JsonSchema.object(
            properties: ["value": JsonSchema.dynamicString()],
            required: ["value"],
            additionalProperties: false
        ),
        returnType: .string
    ) { invocation in
        let template = try invocation.requireString("value")
        return invocation.evaluateInterpolation(template)
    }

    /// Formats a number with grouping separators and a fixed precision.
    public static let formatNumber = FunctionDefinition(
        name: "formatNumber",
        description: "Formats a number with the specified grouping and decimal precision.",
        arguments: JsonSchema.object(
            properties: [
                "value": JsonSchema.dynamicNumber(description: "The number to format."),
                "decimals": JsonSchema.dynamicNumber(description: "Optional. The number of decimal places to show."),
                "grouping": JsonSchema.dynamicBoolean(
                    description: "Optional. If true, uses locale-specific grouping separators. Defaults to true."
                )
            ],
            required: ["value"],
            additionalProperties: false
        ),
        returnType: .string
    ) { invocation in
        let value = try invocation.requireDouble("value")
        return numberFormatter(
            style: .decimal,
            currencyCode: nil,
            decimals: invocation.int("decimals"),
            grouping: invocation.bool("grouping") ?? true,
            locale: invocation.services.locale
        ).string(from: NSNumber(value: value)) ?? Json.stringify(value)
    }

    /// Formats a number as a localized currency amount.
    public static let formatCurrency = FunctionDefinition(
        name: "formatCurrency",
        description: "Formats a number as a currency string.",
        arguments: JsonSchema.object(
            properties: [
                "value": JsonSchema.dynamicNumber(description: "The monetary amount."),
                "currency": JsonSchema.dynamicString(description: "The ISO 4217 currency code (e.g., 'USD', 'EUR')."),
                "decimals": JsonSchema.dynamicNumber(description: "Optional. The number of decimal places to show."),
                "grouping": JsonSchema.dynamicBoolean(
                    description: "Optional. If true, uses locale-specific grouping separators. Defaults to true."
                )
            ],
            required: ["value", "currency"],
            additionalProperties: false
        ),
        returnType: .string
    ) { invocation in
        let value = try invocation.requireDouble("value")
        let currency = try invocation.requireString("currency")
        return numberFormatter(
            style: .currency,
            currencyCode: currency,
            decimals: invocation.int("decimals"),
            grouping: invocation.bool("grouping") ?? true,
            locale: invocation.services.locale
        ).string(from: NSNumber(value: value)) ?? "\(currency) \(Json.stringify(value))"
    }

    /// Formats a date or timestamp with a Unicode TR35 pattern.
    ///
    /// Accepted input values are ISO 8601 strings, `yyyy-MM-dd` dates, `HH:mm`
    /// times and epoch timestamps in seconds or milliseconds.
    public static let formatDate = FunctionDefinition(
        name: "formatDate",
        description: "Formats a timestamp into a string using a Unicode TR35 date pattern.",
        arguments: JsonSchema.object(
            properties: [
                "value": JsonSchema.dynamicValue(description: "The date to format."),
                "format": JsonSchema.dynamicString(description: "A Unicode TR35 date pattern string, e.g. 'MMM dd, yyyy'.")
            ],
            required: ["value", "format"],
            additionalProperties: false
        ),
        returnType: .string
    ) { invocation in
        let pattern = try invocation.requireString("format")
        guard let raw = invocation.value("value") else {
            throw A2uiFunctionError.missingArgument("value", function: "formatDate")
        }
        guard let date = A2uiDateParser.date(from: raw, timeZone: invocation.services.timeZone) else {
            throw A2uiFunctionError.invalidArgument(
                "value",
                function: "formatDate",
                reason: "'\(Json.stringify(raw))' is not a recognized date."
            )
        }
        let formatter = DateFormatter()
        formatter.locale = invocation.services.locale
        formatter.timeZone = invocation.services.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// Selects a string based on the plural category of a count.
    ///
    /// Foundation does not expose the CLDR plural rules, so the `zero`, `one`
    /// and `other` categories are selected and `other` is used as the fallback
    /// for every category a locale does not distinguish.
    public static let pluralize = FunctionDefinition(
        name: "pluralize",
        description: """
        Returns a localized string based on the Common Locale Data Repository (CLDR) plural category of the \
        count (zero, one, two, few, many, other). Requires an 'other' fallback. For English, just use 'one' \
        and 'other'.
        """,
        arguments: JsonSchema.object(
            properties: [
                "value": JsonSchema.dynamicNumber(description: "The numeric value used to determine the plural category."),
                "zero": JsonSchema.dynamicString(description: "String for the 'zero' category."),
                "one": JsonSchema.dynamicString(description: "String for the 'one' category."),
                "two": JsonSchema.dynamicString(description: "String for the 'two' category."),
                "few": JsonSchema.dynamicString(description: "String for the 'few' category."),
                "many": JsonSchema.dynamicString(description: "String for the 'many' category."),
                "other": JsonSchema.dynamicString(description: "The default/fallback string.")
            ],
            required: ["value", "other"],
            additionalProperties: false
        ),
        returnType: .string
    ) { invocation in
        let value = try invocation.requireDouble("value")
        let other = try invocation.requireString("other")
        if value == 0, let zero = invocation.string("zero") { return zero }
        if abs(value) == 1, let one = invocation.string("one") { return one }
        if abs(value) == 2, let two = invocation.string("two") { return two }
        return other
    }

    private static func numberFormatter(
        style: NumberFormatter.Style,
        currencyCode: String?,
        decimals: Int?,
        grouping: Bool,
        locale: Locale
    ) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = style
        formatter.usesGroupingSeparator = grouping
        if let currencyCode {
            formatter.currencyCode = currencyCode
        }
        if let decimals {
            formatter.minimumFractionDigits = decimals
            formatter.maximumFractionDigits = decimals
        } else if style == .decimal {
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 3
        }
        return formatter
    }
}

/// Parses the date representations accepted by A2UI payloads.
public enum A2uiDateParser {
    private static let patterns = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd",
        "HH:mm:ss",
        "HH:mm"
    ]

    /// Converts a JSON value into a date.
    ///
    /// Numbers are treated as epoch seconds, or milliseconds when the value is
    /// large enough that seconds would be implausible.
    public static func date(from value: Any?, timeZone: TimeZone = .current) -> Date? {
        guard let value = Json.normalized(value) else { return nil }
        if let date = value as? Date { return date }

        if !(value is String), let number = Json.double(value) {
            let seconds = abs(number) > 100_000_000_000 ? number / 1000 : number
            return Date(timeIntervalSince1970: seconds)
        }
        guard let string = Json.string(value), !string.isEmpty else { return nil }
        if let date = A2uiTimestamp.date(from: string) { return date }

        for pattern in patterns {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = pattern
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
}
