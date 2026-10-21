import XCTest
@testable import BookReaderIOS

@MainActor
final class SearchCoordinatorTests: XCTestCase {
    func testOnlyEnabledSourcesRunAndConcurrencyIsBounded() async {
        let service = FakeSearchService(results: [:], delayNanoseconds: 20_000_000)
        let coordinator = SearchCoordinator(service: service, maxConcurrency: 2)
        let sources = (0..<4).map { index in
            BookSource(bookSourceName: "源\(index)", bookSourceURL: "https://example.invalid/\(index)", enabled: index != 3, searchURL: "https://example.invalid/search?q={{key}}", ruleSearch: ["bookList": ".book"])
        }

        await coordinator.search("书", sources: sources)

        let snapshot = await service.snapshot()
        XCTAssertEqual(snapshot.startedSourceIDs.count, 3)
        XCTAssertLessThanOrEqual(snapshot.maximumActive, 2)
    }

    func testFailureDoesNotEraseResultsAndDuplicatesKeepEachOrigin() async {
        let first = BookSource(bookSourceName: "一号源", bookSourceURL: "https://example.invalid/one", searchURL: "https://example.invalid/search", ruleSearch: ["bookList": ".book"])
        let second = BookSource(bookSourceName: "二号源", bookSourceURL: "https://example.invalid/two", searchURL: "https://example.invalid/search", ruleSearch: ["bookList": ".book"])
        let book1 = SearchBook(id: "one", title: "同一本书", author: "作者", detailURL: "https://example.invalid/one/book", sourceIDs: [first.id])
        let book2 = SearchBook(id: "two", title: "同一本书", author: "作者", detailURL: "https://example.invalid/two/book", sourceIDs: [second.id])
        let service = FakeSearchService(results: [first.id: .success([book1]), second.id: .failure("站点不可用")])
        let coordinator = SearchCoordinator(service: service, maxConcurrency: 2)

        await coordinator.search("同一本书", sources: [first, second])

        XCTAssertEqual(coordinator.books.count, 1)
        XCTAssertEqual(Set(coordinator.books[0].sourceIDs), [first.id])
        XCTAssertEqual(coordinator.outcomes.filter { if case .failed = $0.status { return true }; return false }.count, 1)
    }
}

private actor FakeSearchService: SourceSearchService {
    enum Result: Sendable { case success([SearchBook]), failure(String) }
    let results: [String: Result]
    let delayNanoseconds: UInt64
    private(set) var startedSourceIDs: [String] = []
    private(set) var active = 0
    private(set) var maximumActive = 0

    init(results: [String: Result], delayNanoseconds: UInt64 = 0) {
        self.results = results
        self.delayNanoseconds = delayNanoseconds
    }

    func search(source: BookSource, keyword: String) async throws -> [SearchBook] {
        startedSourceIDs.append(source.id)
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        if delayNanoseconds > 0 { try? await Task.sleep(nanoseconds: delayNanoseconds) }
        switch results[source.id] ?? .success([]) {
        case .success(let books): return books
        case .failure(let message): throw SourceSearchError.failed(message)
        }
    }

    func snapshot() -> (startedSourceIDs: [String], maximumActive: Int) {
        (startedSourceIDs, maximumActive)
    }
}
