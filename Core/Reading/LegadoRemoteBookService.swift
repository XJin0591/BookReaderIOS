import Foundation

public final class LegadoRemoteBookService: LegadoBookService, @unchecked Sendable {
    private let client: SourceHTTPClient
    private let timeout: Duration

    public init(client: SourceHTTPClient = URLSessionHTTPClient(), timeout: Duration = .seconds(15)) {
        self.client = client
        self.timeout = timeout
    }

    public func detail(for book: SearchBook, source: BookSource) async throws -> BookDetail {
        guard let detailURL = book.detailURL else {
            throw LegadoBookServiceError.invalidURL(stage: .detail, value: "")
        }
        let (html, responseURL) = try await fetchHTML(detailURL, source: source, stage: .detail)
        let title = try value("name", rules: source.ruleBookInfo, html: html, stage: .detail) ?? book.title
        let author = try value("author", rules: source.ruleBookInfo, html: html, stage: .detail)
        let intro = try value("intro", rules: source.ruleBookInfo, html: html, stage: .detail)
        let cover = try value("coverUrl", rules: source.ruleBookInfo, html: html, stage: .detail)
        let toc = try value("tocUrl", rules: source.ruleBookInfo, html: html, stage: .detail)
        let coverURL = try cover.map { try resolve($0, relativeTo: responseURL, stage: .detail) }
        let tocURL = try toc.map { try resolve($0, relativeTo: responseURL, stage: .detail) } ?? responseURL.absoluteString

        return BookDetail(
            id: "\(source.id)|\(book.id)",
            sourceID: source.id,
            title: title,
            author: author,
            intro: intro,
            coverURL: coverURL,
            detailURL: responseURL.absoluteString,
            tocURL: tocURL
        )
    }

    public func chapters(for detail: BookDetail, source: BookSource) async throws -> [BookChapter] {
        let (html, responseURL) = try await fetchHTML(detail.tocURL, source: source, stage: .tableOfContents)
        guard let listRule = source.ruleToc["chapterList"], !listRule.isEmpty else {
            throw LegadoBookServiceError.emptyRule(stage: .tableOfContents, field: "chapterList")
        }
        let blocks = LegadoRuleParser.elements(matching: listRule, from: .string(html))
        guard !blocks.isEmpty else {
            throw LegadoBookServiceError.emptyRule(stage: .tableOfContents, field: "chapterList")
        }

        var chapters: [BookChapter] = []
        for block in blocks {
            let title = try value("chapterName", rules: source.ruleToc, html: block, stage: .tableOfContents)
                ?? LegadoRuleParser.stripHTML(block)
            guard let rawURL = try value("chapterUrl", rules: source.ruleToc, html: block, stage: .tableOfContents) else { continue }
            guard let url = try? resolve(rawURL, relativeTo: responseURL, stage: .tableOfContents) else { continue }
            guard !title.isEmpty else { continue }
            chapters.append(BookChapter(
                id: "\(source.id)|\(detail.id)|\(chapters.count)",
                sourceID: source.id,
                title: title,
                url: url,
                index: chapters.count
            ))
        }
        guard !chapters.isEmpty else {
            throw LegadoBookServiceError.emptyRule(stage: .tableOfContents, field: "chapterUrl")
        }
        return chapters
    }

    public func content(for chapter: BookChapter, source: BookSource) async throws -> ChapterContent {
        let (html, _) = try await fetchHTML(chapter.url, source: source, stage: .content)
        guard let rule = source.ruleContent["content"], !rule.isEmpty else {
            throw LegadoBookServiceError.emptyRule(stage: .content, field: "content")
        }
        let blocks = LegadoRuleParser.elements(matching: rule, from: .string(html))
        let text = blocks.map(LegadoRuleParser.plainText(fromHTML:)).filter { !$0.isEmpty }.joined(separator: "\n")
        guard !text.isEmpty else {
            throw LegadoBookServiceError.emptyRule(stage: .content, field: "content")
        }
        return ChapterContent(chapter: chapter, text: text)
    }

    private func fetchHTML(
        _ value: String,
        source: BookSource,
        stage: LegadoBookServiceStage
    ) async throws -> (String, URL) {
        let url = try validatedURL(value, stage: stage)
        let headers = source.requestHeaders.merging(source.cookie.map { ["Cookie": $0] } ?? [:]) { _, cookie in cookie }
        let request = SourceRequest(url: url, method: "GET", headers: headers, body: nil)
        let (data, response) = try await client.data(for: request, timeout: timeout)
        guard let http = response as? HTTPURLResponse else {
            throw LegadoBookServiceError.invalidResponse(stage: stage)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LegadoBookServiceError.httpStatus(stage: stage, statusCode: http.statusCode)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw LegadoBookServiceError.invalidResponse(stage: stage)
        }
        return (html, response.url ?? url)
    }

    private func value(
        _ field: String,
        rules: [String: String],
        html: String,
        stage: LegadoBookServiceStage
    ) throws -> String? {
        guard let rule = rules[field], !rule.isEmpty else { return nil }
        let values: [RuleValue]
        do {
            values = try LegadoRuleParser.extract(rule, from: .string(html))
        } catch {
            throw LegadoBookServiceError.invalidRule(stage: stage, field: field)
        }
        guard let result = values.first?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
              !result.isEmpty else { return nil }
        return result
    }

    private func validatedURL(_ value: String, stage: LegadoBookServiceStage) throws -> URL {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw LegadoBookServiceError.invalidURL(stage: stage, value: value)
        }
        return url
    }

    private func resolve(_ value: String, relativeTo baseURL: URL, stage: LegadoBookServiceStage) throws -> String {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw LegadoBookServiceError.invalidURL(stage: stage, value: value)
        }
        return url.absoluteString
    }
}
