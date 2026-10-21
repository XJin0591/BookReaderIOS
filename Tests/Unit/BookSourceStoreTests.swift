import XCTest
@testable import BookReaderIOS

@MainActor
final class BookSourceStoreTests: XCTestCase {
    func testImportIsIdempotentToggleAndDelete() throws {
        let store = try makeStore()
        let source = BookSource(bookSourceName: "示例", bookSourceURL: "https://example.invalid/source", enabled: true)

        XCTAssertEqual(try store.importSources([source, source]), 1)
        XCTAssertEqual(try store.all().count, 1)
        try store.setEnabled(false, sourceID: source.id)
        XCTAssertFalse(try XCTUnwrap(store.all().first).enabled)
        try store.delete(sourceID: source.id)
        XCTAssertTrue(try store.all().isEmpty)
        XCTAssertEqual(try store.importSources([source]), 0)
    }

    func testSeedVersionDoesNotOverwriteUserChangesOrResurrectDeletedSources() throws {
        let store = try makeStore()
        let existing = BookSource(bookSourceName: "旧名称", bookSourceURL: "https://example.invalid/existing", enabled: false)
        let deleted = BookSource(bookSourceName: "已删除", bookSourceURL: "https://example.invalid/deleted", enabled: true)
        let added = BookSource(bookSourceName: "新增", bookSourceURL: "https://example.invalid/added", enabled: true)

        _ = try store.importSources([existing, deleted])
        try store.setEnabled(false, sourceID: existing.id)
        try store.delete(sourceID: deleted.id)

        XCTAssertEqual(try store.initializeSeeds([existing, deleted, added], version: 1), 1)
        XCTAssertEqual(try store.initializeSeeds([existing, deleted, added], version: 2), 0)

        let sources = try store.all()
        XCTAssertEqual(sources.map(\.id), [existing.id, added.id])
        XCTAssertFalse(try XCTUnwrap(sources.first(where: { $0.id == existing.id })).enabled)
    }

    private func makeStore() throws -> LocalBookSourceStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try LocalBookSourceStore(fileURL: directory.appendingPathComponent("sources.json"))
    }
}
