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
        return parseBooks(html: html, source: source)
    }

    private func parseBooks(html: String, source: BookSource) -> [SearchBook] {
        guard let listRule = source.ruleSearch["bookList"] else { return [] }
        let blocks = (try? LegadoRuleParser.extract("css:\(listRule)::text", from: .string(html))) ?? []
        return blocks.enumerated().map { index, block in
            let title = block.stringValue
            let url = source.bookSourceURL
            return SearchBook(id: "\(source.id)#\(index)", title: title, author: nil, detailURL: url, sourceIDs: [source.id])
        }
    }
}
