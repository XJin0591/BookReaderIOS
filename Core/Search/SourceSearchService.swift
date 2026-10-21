import Foundation

public protocol SourceSearchService: Sendable {
    func search(source: BookSource, keyword: String) async throws -> [SearchBook]
}

public final class LegadoSourceSearchService: SourceSearchService, @unchecked Sendable {
    private let client: SourceHTTPClient
    private let timeout: Duration

    public init(client: SourceHTTPClient = URLSessionHTTPClient(), timeout: Duration = .seconds(15)) {
        self.client = client
        self.timeout = timeout
    }

    public func search(source: BookSource, keyword: String) async throws -> [SearchBook] {
        guard let searchURL = source.searchURL, !searchURL.isEmpty else { return [] }
        let request = try SourceRequest(urlTemplate: searchURL, method: "GET", headers: source.requestHeaders.merging(source.cookie.map { ["Cookie": $0] } ?? [:]) { _, new in new }, bodyTemplate: nil, values: ["key": keyword, "keyword": keyword])
        let (data, response) = try await client.data(for: request, timeout: timeout)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw SourceSearchError.failed("HTTP 请求失败") }
        guard let html = String(data: data, encoding: .utf8) else { throw SourceSearchError.failed("响应不是 UTF-8 文本") }
        return parseBooks(html: html, responseURL: response.url ?? request.url, source: source)
    }

    private func parseBooks(html: String, responseURL: URL, source: BookSource) -> [SearchBook] {
        guard let listRule = source.ruleSearch["bookList"] else { return [] }
        let blocks = LegadoRuleParser.elements(matching: listRule, from: .string(html))
        return blocks.enumerated().compactMap { index, block in
            let title = field("name", in: block, source: source) ?? LegadoRuleParser.stripHTML(block)
            guard !title.isEmpty else { return nil }
            let author = field("author", in: block, source: source)
            let detailURL = field("bookUrl", in: block, source: source).flatMap { resolve($0, relativeTo: responseURL) }
            return SearchBook(id: "\(source.id)#\(index)", title: title, author: author, detailURL: detailURL, sourceIDs: [source.id])
        }
    }

    private func field(_ name: String, in block: String, source: BookSource) -> String? {
        guard let rule = source.ruleSearch[name],
              let value = try? LegadoRuleParser.extract(rule, from: .string(block)).first?.stringValue
        else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resolve(_ value: String, relativeTo baseURL: URL) -> String? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else { return nil }
        return url.absoluteString
    }
}
