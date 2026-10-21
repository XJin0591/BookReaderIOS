import XCTest
@testable import BookReaderIOS

@MainActor
final class BookDetailViewModelTests: XCTestCase {
    func testLoadsDetailAndChaptersAndCanRetryAfterFailure() async throws {
        let detail = BookDetail(
            id: "source|book",
            sourceID: "source",
            title: "测试书",
            author: "作者",
            intro: "简介",
            coverURL: nil,
            detailURL: "https://example.invalid/book",
            tocURL: "https://example.invalid/toc"
        )
        let chapter = BookChapter(id: "chapter-0", sourceID: "source", title: "第一章", url: "https://example.invalid/chapter/1", index: 0)
        let service = FakeBookDetailService(detail: detail, chapters: [chapter], detailFailuresRemaining: 1)
        let model = BookDetailViewModel(service: service)
        let source = BookSource(bookSourceName: "源", bookSourceURL: "https://example.invalid")
        let book = SearchBook(id: "book", title: "搜索名", author: nil, detailURL: detail.detailURL, sourceIDs: [source.id])

        await model.load(book: book, source: source)

        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.detail)
        XCTAssertTrue(model.chapters.isEmpty)
        XCTAssertNotNil(model.errorMessage)

        await model.load(book: book, source: source)

        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.detail, detail)
        XCTAssertEqual(model.chapters, [chapter])
    }
}

private actor FakeBookDetailService: LegadoBookService {
    private let detailValue: BookDetail
    private let chaptersValue: [BookChapter]
    private var detailFailuresRemaining: Int

    init(detail: BookDetail, chapters: [BookChapter], detailFailuresRemaining: Int) {
        self.detailValue = detail
        self.chaptersValue = chapters
        self.detailFailuresRemaining = detailFailuresRemaining
    }

    func detail(for book: SearchBook, source: BookSource) async throws -> BookDetail {
        if detailFailuresRemaining > 0 {
            detailFailuresRemaining -= 1
            throw FakeBookDetailError.failed
        }
        return detailValue
    }

    func chapters(for detail: BookDetail, source: BookSource) async throws -> [BookChapter] {
        chaptersValue
    }

    func content(for chapter: BookChapter, source: BookSource) async throws -> ChapterContent {
        ChapterContent(chapter: chapter, text: "正文")
    }
}

private enum FakeBookDetailError: Error {
    case failed
}
