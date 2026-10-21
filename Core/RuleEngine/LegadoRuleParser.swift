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
        let selectorBase = String(simple.split(separator: "[").first ?? "")
        let tag: String? = {
            guard !selectorBase.hasPrefix(".") && !selectorBase.hasPrefix("#") else { return nil }
            let value = selectorBase.split(separator: ".").first.map(String.init) ?? selectorBase
            return value.split(separator: "#").first.map(String.init)
        }()
        let className: String? = {
            guard let dot = selectorBase.firstIndex(of: ".") else { return nil }
            let value = selectorBase[selectorBase.index(after: dot)...]
            return String(value).split(separator: "#").first.map(String.init)
        }()
        let id: String? = {
            guard let hash = selectorBase.firstIndex(of: "#") else { return nil }
            let value = selectorBase[selectorBase.index(after: hash)...]
            return String(value).split(separator: ".").first.map(String.init)
        }()
        let classAttribute: String? = {
            guard let expression = try? NSRegularExpression(pattern: #"\[\s*class\s*=\s*['\"]([^'\"]+)['\"]\s*\]"#),
                  let match = expression.firstMatch(in: simple, range: NSRange(simple.startIndex..., in: simple)),
                  let range = Range(match.range(at: 1), in: simple) else { return nil }
            return String(simple[range])
        }()
        let tagPattern = tag.map { NSRegularExpression.escapedPattern(for: $0) } ?? "[A-Za-z][A-Za-z0-9:_-]*"
        var conditions = ""
        if let className {
            let escaped = NSRegularExpression.escapedPattern(for: className)
            conditions += "(?=[^>]*\\bclass\\s*=\\s*[\\\"'][^\\\"']*\\b\(escaped)\\b[^\\\"']*[\\\"'])"
        }
        if let id {
            let escaped = NSRegularExpression.escapedPattern(for: id)
            conditions += "(?=[^>]*\\bid\\s*=\\s*[\\\"']\(escaped)[\\\"'])"
        }
        if let classAttribute {
            let escaped = NSRegularExpression.escapedPattern(for: classAttribute)
            conditions += "(?=[^>]*\\bclass\\s*=\\s*[\\\"']\(escaped)[\\\"'])"
        }
        let pattern = "<(\(tagPattern))\\b\(conditions)[^>]*>([\\s\\S]*?)</\\1\\s*>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let tagRange = Range(match.range(at: 1), in: html), let bodyRange = Range(match.range(at: 2), in: html) else { return nil }
            let actualTag = String(html[tagRange])
            guard (tag == nil || tag == actualTag), let fullRange = Range(match.range, in: html) else { return nil }
            let full = String(html[fullRange])
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
