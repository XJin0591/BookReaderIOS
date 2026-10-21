import XCTest
@testable import BookReaderIOS

final class LegadoBookServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReadingFixtureURLProtocol.responses = []
        ReadingFixtureURLProtocol.requests = []
    }

    func testLoadsDetailsChaptersAndContentWithRelativeURLsAndSourceHeaders() async throws {
        ReadingFixtureURLProtocol.responses = [
            .init(body: Data("""
            <h1 class="title">测试书</h1>
            <span class="author">作者甲</span>
            <div class="intro">简介文本</div>
            <a class="cover" href="/cover.jpg">封面</a>
            <a id="toc" href="/book/toc">目录</a>
            """.utf8)),
            .init(body: Data("""
            <ul>
              <li class="chapter"><a href="/chapter/1">第一章</a></li>
              <li class="chapter"><a href="https://cdn.example.invalid/chapter/2">第二章</a></li>
            </ul>
            """.utf8)),
            .init(body: Data("<div class=\"content\"><p>第一段</p><p>第二段</p></div>".utf8))
        ]
        let source = makeSource()
        let service = makeService()
        let book = SearchBook(
            id: "book-1",
            title: "搜索书名",
            author: nil,
            detailURL: "https://example.invalid/book/1",
            sourceIDs: [source.id]
        )

        let detail = try await service.detail(for: book, source: source)
        XCTAssertEqual(detail.title, "测试书")
        XCTAssertEqual(detail.author, "作者甲")
        XCTAssertEqual(detail.intro, "简介文本")
        XCTAssertEqual(detail.coverURL, "https://example.invalid/cover.jpg")
        XCTAssertEqual(detail.tocURL, "https://example.invalid/book/toc")

        let chapters = try await service.chapters(for: detail, source: source)
        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(chapters.map(\.url), [
            "https://example.invalid/chapter/1",
            "https://cdn.example.invalid/chapter/2"
        ])
        XCTAssertEqual(chapters.map(\.index), [0, 1])

        let content = try await service.content(for: chapters[0], source: source)
        XCTAssertEqual(content.text, "第一段\n第二段")
        XCTAssertEqual(ReadingFixtureURLProtocol.requests.count, 3)
        XCTAssertTrue(ReadingFixtureURLProtocol.requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Source") == "fixture" })
        XCTAssertTrue(ReadingFixtureURLProtocol.requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == "sid=reading" })
    }

    func testHTTPFailureReportsStageAndStatusCode() async {
        ReadingFixtureURLProtocol.responses = [.init(statusCode: 503, body: Data())]
        let source = makeSource()
        let book = SearchBook(id: "book-1", title: "书", author: nil, detailURL: "https://example.invalid/book/1", sourceIDs: [source.id])

        do {
            _ = try await makeService().detail(for: book, source: source)
            XCTFail("Expected HTTP error")
        } catch LegadoBookServiceError.httpStatus(stage: .detail, statusCode: 503) {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsInvalidDetailURL() async {
        let source = makeSource()
        let book = SearchBook(id: "book-1", title: "书", author: nil, detailURL: "file:///tmp/book", sourceIDs: [source.id])

        do {
            _ = try await makeService().detail(for: book, source: source)
            XCTFail("Expected invalid URL error")
        } catch LegadoBookServiceError.invalidURL(stage: .detail, _) {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEmptyChapterListRuleReportsTableOfContentsStage() async {
        ReadingFixtureURLProtocol.responses = [.init(body: Data("<div>无章节</div>".utf8))]
        var source = makeSource()
        source = BookSource(
            bookSourceName: source.bookSourceName,
            bookSourceURL: source.bookSourceURL,
            ruleToc: ["chapterList": ".missing"]
        )
        let detail = BookDetail(
            id: "book-1",
            sourceID: source.id,
            title: "书",
            author: nil,
            intro: nil,
            coverURL: nil,
            detailURL: "https://example.invalid/book/1",
            tocURL: "https://example.invalid/book/toc"
        )

        do {
            _ = try await makeService().chapters(for: detail, source: source)
            XCTFail("Expected empty rule error")
        } catch LegadoBookServiceError.emptyRule(stage: .tableOfContents, field: "chapterList") {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeSource() -> BookSource {
        BookSource(
            bookSourceName: "阅读源",
            bookSourceURL: "https://example.invalid",
            ruleBookInfo: [
                "name": "css:.title::text",
                "author": "css:.author::text",
                "intro": "css:.intro::text",
                "coverUrl": "css:.cover@href",
                "tocUrl": "css:#toc@href"
            ],
            ruleToc: [
                "chapterList": ".chapter",
                "chapterName": "css:a::text",
                "chapterUrl": "css:a@href"
            ],
            ruleContent: ["content": "css:.content::text"],
            requestHeaders: ["X-Source": "fixture"],
            cookie: "sid=reading"
        )
    }

    private func makeService() -> LegadoRemoteBookService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReadingFixtureURLProtocol.self]
        return LegadoRemoteBookService(client: URLSessionHTTPClient(configuration: configuration))
    }
}

private final class ReadingFixtureURLProtocol: URLProtocol {
    struct Response {
        var statusCode: Int
        var body: Data

        init(statusCode: Int = 200, body: Data) {
            self.statusCode = statusCode
            self.body = body
        }
    }

    static var responses: [Response] = []
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let fixture = Self.responses.isEmpty ? Response(statusCode: 500, body: Data()) : Self.responses.removeFirst()
        let url = request.url ?? URL(string: "https://example.invalid")!
        let response = HTTPURLResponse(url: url, statusCode: fixture.statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: fixture.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
