import Foundation

public enum LegadoRuleParserError: LocalizedError, Equatable {
    case unsupportedRule(String)
    case invalidRegex(String)
    public var errorDescription: String? { "书源规则无效：\(String(describing: self))" }
}

public enum LegadoRuleParser {
    public static func extract(_ rule: String, from input: RuleValue) throws -> [RuleValue] {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("regex:") { return try regex(String(trimmed.dropFirst(6)), from: input.stringValue) }
        if trimmed.hasPrefix("json:") || trimmed.hasPrefix("jsonpath:") {
            let prefix = trimmed.hasPrefix("jsonpath:") ? 9 : 5
            return jsonPath(String(trimmed.dropFirst(prefix)), from: input)
        }
        if trimmed.hasPrefix("xpath:") { return html(String(trimmed.dropFirst(6)), input: input, mode: .xpath) }
        if trimmed.hasPrefix("css:") { return html(String(trimmed.dropFirst(4)), input: input, mode: .css) }
        throw LegadoRuleParserError.unsupportedRule(trimmed)
    }

    private enum HTMLMode { case css, xpath }

    private static func html(_ selector: String, input: RuleValue, mode: HTMLMode) -> [RuleValue] {
        let html = input.stringValue
        let normalized: String
        let extraction: Extraction
        switch mode {
        case .css:
            if selector.hasSuffix("::text") { normalized = String(selector.dropLast(6)); extraction = .text }
            else if let at = selector.lastIndex(of: "@") { normalized = String(selector[..<at]); extraction = .attribute(String(selector[selector.index(after: at)...])) }
            else { normalized = selector; extraction = .text }
        case .xpath:
            if selector.hasSuffix("/text()") { normalized = String(selector.dropLast(7)); extraction = .text }
            else if selector.contains("/@") { let parts = selector.split(separator: "/"); normalized = parts.dropLast().joined(separator: "/"); extraction = .attribute(String(parts.last!).replacingOccurrences(of: "@", with: "")) }
            else { normalized = selector; extraction = .text }
        }

        let simple = normalized.replacingOccurrences(of: "^//", with: "", options: .regularExpression)
        let tag = simple.split(separator: "[").first.map(String.init)?.split(separator: ".").first.map(String.init)?.split(separator: "#").first.map(String.init)
        let className = simple.split(separator: ".").dropFirst().first.map(String.init)?.split(separator: "[").first.map(String.init)
        let id = simple.split(separator: "#").dropFirst().first.map(String.init)?.split(separator: "[").first.map(String.init)
        let classAttribute = simple.firstIndex(of: "'").flatMap { start in simple[start...].dropFirst().firstIndex(of: "'") }.map { _ in
            let pieces = simple.split(separator: "'")
            return pieces.count > 1 ? String(pieces[1]) : nil
        } ?? nil
        let pattern = #"<([A-Za-z][A-Za-z0-9:_-]*)(?:\s+[^>]*)?>([\s\S]*?)</\1\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let tagRange = Range(match.range(at: 1), in: html), let bodyRange = Range(match.range(at: 2), in: html) else { return nil }
            let actualTag = String(html[tagRange])
            guard (tag == nil || tag == actualTag), let fullRange = Range(match.range, in: html) else { return nil }
            let full = String(html[fullRange])
            guard className == nil || full.contains("class=\"\(className!)\"") || full.contains("class='\(className!)'") else { return nil }
            guard id == nil || full.contains("id=\"\(id!)\"") || full.contains("id='\(id!)'") else { return nil }
            guard classAttribute == nil || full.contains("class=\"\(classAttribute!)\"") || full.contains("class='\(classAttribute!)'") else { return nil }
            let body = String(html[bodyRange])
            switch extraction {
            case .text: return .string(Self.stripTags(body))
            case .attribute(let name): return Self.attribute(name, from: full).map(RuleValue.string)
            }
        }
    }

    private enum Extraction { case text, attribute(String) }

    private static func attribute(_ name: String, from html: String) -> String? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*[\\\"']([^\\\"']*)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)), let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }

    private static func stripTags(_ value: String) -> String {
        value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func regex(_ pattern: String, from value: String) throws -> [RuleValue] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { throw LegadoRuleParserError.invalidRegex(pattern) }
        return expression.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
            let index = match.numberOfRanges > 1 ? 1 : 0
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return .string(String(value[range]))
        }
    }

    private static func jsonPath(_ path: String, from input: RuleValue) -> [RuleValue] {
        var values = [input]
        var tokens = path.trimmingCharacters(in: CharacterSet(charactersIn: "$.")).split(separator: ".").map(String.init)
        while !tokens.isEmpty {
            let token = tokens.removeFirst()
            if token == "[*]" { values = values.flatMap { if case .array(let items) = $0 { return items }; return [] } }
            else if token.hasSuffix("[*]") { let key = String(token.dropLast(3)); values = values.flatMap { if case .object(let object) = $0, case .array(let items)? = object[key] { return items }; return [] } }
            else if let indexStart = token.firstIndex(of: "["), token.hasSuffix("]") { let key = String(token[..<indexStart]); let index = Int(token[token.index(after: indexStart)..<token.index(before: token.endIndex)]) ?? -1; values = values.compactMap { if case .object(let object) = $0, case .array(let items)? = object[key], items.indices.contains(index) { return items[index] }; return nil } }
            else { values = values.compactMap { if case .object(let object) = $0 { return object[token] }; return nil } }
        }
        return values
    }
}
