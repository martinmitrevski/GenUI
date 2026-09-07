//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// A parsed `${...}` expression from a `formatString` template.
///
/// The A2UI `formatString` function interpolates data model paths and renderer
/// side function calls into a string. This type is the parsed form of one such
/// expression, ready to be evaluated by ``ExpressionEvaluator``.
public enum A2uiExpression: Equatable {
    /// A data model path, absolute or relative to the current scope.
    case path(DataPath)

    /// A function call with named arguments.
    case call(name: String, arguments: [String: A2uiExpression])

    /// A literal value written inline in the template.
    case literal(Any)

    /// Compares two expressions structurally.
    public static func == (lhs: A2uiExpression, rhs: A2uiExpression) -> Bool {
        switch (lhs, rhs) {
        case let (.path(left), .path(right)):
            return left == right
        case let (.literal(left), .literal(right)):
            return Json.isEqual(left, right)
        case let (.call(leftName, leftArgs), .call(rightName, rightArgs)):
            guard leftName == rightName, leftArgs.keys == rightArgs.keys else { return false }
            return leftArgs.allSatisfy { key, value in rightArgs[key] == value }
        default:
            return false
        }
    }
}

/// One piece of a parsed `formatString` template.
public enum A2uiTemplateSegment: Equatable {
    /// Literal text copied verbatim into the output.
    case text(String)

    /// An expression whose evaluated value is interpolated.
    case expression(A2uiExpression)
}

/// Parses `formatString` templates and the expressions inside them.
///
/// Grammar, as defined by the A2UI v1.0 specification:
///
/// * `${/absolute/path}` and `${relative/path}` interpolate the data model.
/// * `${functionName(arg: value, other: ${/path})}` calls a renderer function.
/// * Arguments are named, and values may be quoted strings, numbers, booleans,
///   nested `${...}` expressions or nested calls.
/// * A literal `${` is written as `\${`.
public enum A2uiExpressionParser {
    /// Splits a template into literal text and expression segments.
    /// Unterminated expressions are kept as literal text.
    public static func parseTemplate(_ template: String) -> [A2uiTemplateSegment] {
        var segments: [A2uiTemplateSegment] = []
        var text = ""
        let characters = Array(template)
        var index = 0

        while index < characters.count {
            if characters[index] == "\\", index + 2 < characters.count,
               characters[index + 1] == "$", characters[index + 2] == "{" {
                text.append("${")
                index += 3
                continue
            }
            if characters[index] == "$", index + 1 < characters.count, characters[index + 1] == "{" {
                guard let closing = matchingBrace(characters, openingAt: index + 1) else {
                    text.append(characters[index])
                    index += 1
                    continue
                }
                if !text.isEmpty {
                    segments.append(.text(text))
                    text = ""
                }
                let source = String(characters[(index + 2)..<closing])
                if let expression = parseExpression(source) {
                    segments.append(.expression(expression))
                } else {
                    genUiLogger.warning("Could not parse formatString expression '\(source)'.")
                }
                index = closing + 1
                continue
            }
            text.append(characters[index])
            index += 1
        }

        if !text.isEmpty {
            segments.append(.text(text))
        }
        return segments
    }

    /// Parses a single expression, without the surrounding `${}`.
    /// Returns `nil` when the expression is empty or malformed.
    public static func parseExpression(_ source: String) -> A2uiExpression? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let call = parseCall(trimmed) {
            return call
        }
        return parseValue(trimmed)
    }

    // MARK: - Private

    private static func parseCall(_ source: String) -> A2uiExpression? {
        guard source.hasSuffix(")"), let parenIndex = source.firstIndex(of: "(") else { return nil }
        let name = String(source[source.startIndex..<parenIndex]).trimmingCharacters(in: .whitespaces)
        guard isFunctionName(name) else { return nil }

        let argsStart = source.index(after: parenIndex)
        let argsEnd = source.index(before: source.endIndex)
        guard argsStart <= argsEnd else { return nil }
        let argsSource = String(source[argsStart..<argsEnd])

        var arguments: [String: A2uiExpression] = [:]
        for (offset, part) in splitTopLevel(argsSource, separator: ",").enumerated() {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let colon = topLevelColon(in: trimmed) {
                let key = String(trimmed[trimmed.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if let expression = parseValue(value) {
                    arguments[key] = expression
                }
            } else if offset == 0, let expression = parseValue(trimmed) {
                // Tolerate a single positional argument by mapping it to `value`.
                arguments["value"] = expression
            }
        }
        return .call(name: name, arguments: arguments)
    }

    private static func parseValue(_ source: String) -> A2uiExpression? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("${"), trimmed.hasSuffix("}") {
            let inner = String(trimmed.dropFirst(2).dropLast())
            return parseExpression(inner)
        }
        if let call = parseCall(trimmed) {
            return call
        }
        if let quoted = unquote(trimmed) {
            return .literal(quoted)
        }
        if trimmed == "true" { return .literal(true) }
        if trimmed == "false" { return .literal(false) }
        if trimmed == "null" { return .literal(NSNull()) }
        if let number = Double(trimmed) {
            return .literal(number)
        }
        return .path(DataPath(trimmed))
    }

    private static func unquote(_ source: String) -> String? {
        guard source.count >= 2 else { return nil }
        let first = source.first
        guard first == "'" || first == "\"", source.last == first else { return nil }
        return String(source.dropFirst().dropLast())
            .replacingOccurrences(of: "\\'", with: "'")
            .replacingOccurrences(of: "\\\"", with: "\"")
    }

    private static func isFunctionName(_ name: String) -> Bool {
        guard let first = name.first else { return false }
        guard first == "@" || first.isLetter || first == "_" else { return false }
        let rest = name.dropFirst()
        return rest.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static func matchingBrace(_ characters: [Character], openingAt index: Int) -> Int? {
        var depth = 0
        var cursor = index
        var quote: Character?

        while cursor < characters.count {
            let character = characters[cursor]
            if let openQuote = quote {
                if character == "\\" {
                    cursor += 2
                    continue
                }
                if character == openQuote { quote = nil }
                cursor += 1
                continue
            }
            switch character {
            case "'", "\"":
                quote = character
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return cursor }
            default:
                break
            }
            cursor += 1
        }
        return nil
    }

    private static func splitTopLevel(_ source: String, separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        var iterator = source.makeIterator()
        var escaped = false

        while let character = iterator.next() {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\" {
                current.append(character)
                escaped = true
                continue
            }
            if let openQuote = quote {
                current.append(character)
                if character == openQuote { quote = nil }
                continue
            }
            switch character {
            case "'", "\"":
                quote = character
                current.append(character)
            case "(", "{", "[":
                depth += 1
                current.append(character)
            case ")", "}", "]":
                depth -= 1
                current.append(character)
            case separator where depth == 0:
                parts.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        parts.append(current)
        return parts
    }

    private static func topLevelColon(in source: String) -> String.Index? {
        var depth = 0
        var quote: Character?
        var index = source.startIndex

        while index < source.endIndex {
            let character = source[index]
            if let openQuote = quote {
                if character == openQuote { quote = nil }
                index = source.index(after: index)
                continue
            }
            switch character {
            case "'", "\"":
                quote = character
            case "(", "{", "[":
                depth += 1
            case ")", "}", "]":
                depth -= 1
            case ":" where depth == 0:
                return index
            default:
                break
            }
            index = source.index(after: index)
        }
        return nil
    }
}
