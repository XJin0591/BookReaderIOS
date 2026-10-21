import Foundation

public protocol LegadoBookService: Sendable {
    func detail(for book: SearchBook, source: BookSource) async throws -> BookDetail
    func chapters(for detail: BookDetail, source: BookSource) async throws -> [BookChapter]
    func content(for chapter: BookChapter, source: BookSource) async throws -> ChapterContent
}
