import XCTest
@testable import BookReaderIOS

final class SourceSearchServiceTests: XCTestCase {
    func testSearchExtractsBookFieldsAndResolvesDetailURLs() async throws {
        SearchFixtureURLProtocol.body = Data("""
        <div class="book"><a href="/book/1"><h2>书名一</h2></a><span class="author">作者一</span></div>
        <div class="book"><a href="https://cdn.example.invalid/book/2"><h2>书名二</h2></a></div>
        <div class="book"><h2>没有详情地址</h2></div>
        """.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SearchFixtureURLProtocol.self]
        let service = LegadoSourceSearchService(client: URLSessionHTTPClient(configuration: configuration))
        let source = BookSource(
            bookSourceName: "测试源",
            bookSourceURL: "https://example.invalid",
            searchURL: "https://example.invalid/search?q={{key}}",
            ruleSearch: [
                "bookList": ".book",
                "name": "css:h2::text",
                "author": "css:.author::text",
                "bookUrl": "css:a@href"
            ]
        )

        let books = try await service.search(source: source, keyword: "书名")

        XCTAssertEqual(books.map(\.title), ["书名一", "书名二", "没有详情地址"])
        XCTAssertEqual(books[0].author, "作者一")
        XCTAssertNil(books[1].author)
        XCTAssertEqual(books[0].detailURL, "https://example.invalid/book/1")
        XCTAssertEqual(books[1].detailURL, "https://cdn.example.invalid/book/2")
        XCTAssertNil(books[2].detailURL)
        XCTAssertEqual(books.map(\.sourceIDs), [[source.id], [source.id], [source.id]])
    }

    func testDetailDestinationUsesOnlyValidHTTPURLForSelectedSource() {
        let book = SearchBook(
            id: "book",
            title: "书",
            author: nil,
            detailURL: "https://first.example.invalid/book",
            sourceIDs: ["first", "second"],
            detailURLsBySource: [
                "first": "https://first.example.invalid/book",
                "second": "javascript:alert(1)"
            ]
        )
        XCTAssertEqual(book.resolvedDetailURL(forSourceID: "first")?.absoluteString, "https://first.example.invalid/book")
        XCTAssertNil(book.resolvedDetailURL(forSourceID: "second"))

        let missing = SearchBook(id: "missing", title: "缺链接", author: nil, detailURL: nil, sourceIDs: ["third"])
        XCTAssertNil(missing.resolvedDetailURL(forSourceID: "third"))
    }
}

private final class SearchFixtureURLProtocol: URLProtocol {
    static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(string: "https://example.invalid")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
