import Foundation

public struct SourceRequest: Sendable {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let body: Data?

    public init(url: URL, method: String, headers: [String: String], body: Data?) {
        self.url = url
        self.method = method.uppercased()
        self.headers = headers
        self.body = body
    }

    public init(urlTemplate: String, method: String, headers: [String: String], bodyTemplate: String?, values: [String: String]) throws {
        let urlString = try Self.interpolateURL(urlTemplate, values: values)
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
            throw SourceRequestError.invalidURL(urlString)
        }
        let body = bodyTemplate.flatMap { Self.interpolate($0, values: values).data(using: .utf8) }
        self.init(url: url, method: method, headers: headers, body: body)
    }

    private static func interpolateURL(_ template: String, values: [String: String]) throws -> String {
        var output = template
        let pattern = #"\{\{([^{}]+)\}\}"#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: template, range: NSRange(template.startIndex..., in: template))
        for match in matches.reversed() {
            guard let keyRange = Range(match.range(at: 1), in: template) else { continue }
            let key = String(template[keyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = values[key] ?? ""
            let escaped = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))) ?? value
            if let range = Range(match.range, in: output) { output.replaceSubrange(range, with: escaped) }
        }
        return output
    }

    private static func interpolate(_ template: String, values: [String: String]) -> String {
        values.reduce(template) { $0.replacingOccurrences(of: "{{\($1.key)}}", with: $1.value) }
    }
}

public enum SourceRequestError: LocalizedError, Equatable {
    case invalidURL(String)
    public var errorDescription: String? {
        if case .invalidURL(let value) = self { return "书源请求地址无效：\(value)" }
        return nil
    }
}
