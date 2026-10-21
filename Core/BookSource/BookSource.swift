import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct BookSource: Codable, Identifiable, Equatable, Sendable {
    public let bookSourceName: String
    public let bookSourceURL: String
    public var enabled: Bool
    public let searchURL: String?
    public let ruleSearch: [String: String]
    public let ruleBookInfo: [String: String]
    public let ruleToc: [String: String]
    public let ruleContent: [String: String]
    public let requestHeaders: [String: String]
    public let cookie: String?
    public let additionalFields: [String: JSONValue]

    public var id: String { Self.normalizeURL(bookSourceURL) }

    public init(
        bookSourceName: String,
        bookSourceURL: String,
        enabled: Bool = true,
        searchURL: String? = nil,
        ruleSearch: [String: String] = [:],
        ruleBookInfo: [String: String] = [:],
        ruleToc: [String: String] = [:],
        ruleContent: [String: String] = [:],
        requestHeaders: [String: String] = [:],
        cookie: String? = nil,
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.bookSourceName = bookSourceName
        self.bookSourceURL = Self.normalizeURL(bookSourceURL)
        self.enabled = enabled
        self.searchURL = searchURL
        self.ruleSearch = ruleSearch
        self.ruleBookInfo = ruleBookInfo
        self.ruleToc = ruleToc
        self.ruleContent = ruleContent
        self.requestHeaders = requestHeaders
        self.cookie = cookie
        self.additionalFields = additionalFields
    }

    enum CodingKeys: String, CodingKey {
        case bookSourceName, bookSourceUrl, enabled, searchUrl, ruleSearch, ruleBookInfo, ruleToc, ruleContent, header, cookie
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let name = try container.decode(String.self, forKey: DynamicCodingKey("bookSourceName"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = try container.decode(String.self, forKey: DynamicCodingKey("bookSourceUrl"))
        guard !name.isEmpty else { throw BookSourceImportError.invalidRecord("bookSourceName 不能为空") }
        guard let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased(), ["http", "https"].contains(scheme), parsed.host != nil else {
            throw BookSourceImportError.invalidRecord("bookSourceUrl 必须是 HTTP(S) 地址")
        }

        let enabled = try container.decodeIfPresent(Bool.self, forKey: DynamicCodingKey("enabled")) ?? true
        let searchURL = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("searchUrl"))
        let ruleSearch = try container.decodeIfPresent([String: String].self, forKey: DynamicCodingKey("ruleSearch")) ?? [:]
        let ruleBookInfo = try container.decodeIfPresent([String: String].self, forKey: DynamicCodingKey("ruleBookInfo")) ?? [:]
        let ruleToc = try container.decodeIfPresent([String: String].self, forKey: DynamicCodingKey("ruleToc")) ?? [:]
        let ruleContent = try container.decodeIfPresent([String: String].self, forKey: DynamicCodingKey("ruleContent")) ?? [:]
        let headers = try container.decodeIfPresent([String: String].self, forKey: DynamicCodingKey("header")) ?? [:]
        let cookie = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("cookie"))
        let known = Set(["bookSourceName", "bookSourceUrl", "enabled", "searchUrl", "ruleSearch", "ruleBookInfo", "ruleToc", "ruleContent", "header", "cookie"])
        var additional: [String: JSONValue] = [:]
        for key in container.allKeys where !known.contains(key.stringValue) {
            additional[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }

        self.init(bookSourceName: name, bookSourceURL: url, enabled: enabled, searchURL: searchURL, ruleSearch: ruleSearch, ruleBookInfo: ruleBookInfo, ruleToc: ruleToc, ruleContent: ruleContent, requestHeaders: headers, cookie: cookie, additionalFields: additional)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(bookSourceName, forKey: DynamicCodingKey("bookSourceName"))
        try container.encode(bookSourceURL, forKey: DynamicCodingKey("bookSourceUrl"))
        try container.encode(enabled, forKey: DynamicCodingKey("enabled"))
        try container.encodeIfPresent(searchURL, forKey: DynamicCodingKey("searchUrl"))
        try container.encode(ruleSearch, forKey: DynamicCodingKey("ruleSearch"))
        try container.encode(ruleBookInfo, forKey: DynamicCodingKey("ruleBookInfo"))
        try container.encode(ruleToc, forKey: DynamicCodingKey("ruleToc"))
        try container.encode(ruleContent, forKey: DynamicCodingKey("ruleContent"))
        try container.encode(requestHeaders, forKey: DynamicCodingKey("header"))
        try container.encodeIfPresent(cookie, forKey: DynamicCodingKey("cookie"))
        for (key, value) in additionalFields { try container.encode(value, forKey: DynamicCodingKey(key)) }
    }

    public static func normalizeURL(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.last == "/" { result.removeLast() }
        guard var components = URLComponents(string: result) else { return result.lowercased() }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.string ?? result.lowercased()
    }
}

struct DynamicCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int? = nil
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}
