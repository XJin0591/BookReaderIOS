import XCTest
@testable import BookReaderIOS

@MainActor
final class ChapterReaderViewModelTests: XCTestCase {
    func testLoadsChapterContentAndCanRetryAfterFailure() async {
        let chapter = BookChapter(
            id: "chapter-0",
            sourceID: "source",
            title: "第一章",
            url: "https://example.invalid/chapter/1",
            index: 0
        )
        let content = ChapterContent(chapter: chapter, text: "第一段\n第二段")
        let service = FakeChapterReaderService(content: content, failuresRemaining: 1)
        let model = ChapterReaderViewModel(service: service)
        let source = BookSource(bookSourceName: "源", bookSourceURL: "https://example.invalid")

        await model.load(chapter: chapter, source: source)

        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.content)
        XCTAssertNotNil(model.errorMessage)

        await model.load(chapter: chapter, source: source)

        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.content, content)
    }
}

private actor FakeChapterReaderService: LegadoBookService {
    private let contentValue: ChapterContent
    private var failuresRemaining: Int

    init(content: ChapterContent, failuresRemaining: Int) {
        self.contentValue = content
        self.failuresRemaining = failuresRemaining
    }

    func detail(for book: SearchBook, source: BookSource) async throws -> BookDetail {
        throw FakeChapterReaderError.unexpectedCall
    }

    func chapters(for detail: BookDetail, source: BookSource) async throws -> [BookChapter] {
        throw FakeChapterReaderError.unexpectedCall
    }

    func content(for chapter: BookChapter, source: BookSource) async throws -> ChapterContent {
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw FakeChapterReaderError.failed
        }
        return contentValue
    }
}

private enum FakeChapterReaderError: Error {
    case failed
    case unexpectedCall
}
