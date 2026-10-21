import Combine
import Foundation

@MainActor
final class BookDetailViewModel: ObservableObject {
    @Published private(set) var detail: BookDetail?
    @Published private(set) var chapters: [BookChapter] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service: LegadoBookService

    init(service: LegadoBookService = LegadoRemoteBookService()) {
        self.service = service
    }

    func load(book: SearchBook, source: BookSource) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedDetail = try await service.detail(for: book, source: source)
            let loadedChapters = try await service.chapters(for: loadedDetail, source: source)
            detail = loadedDetail
            chapters = loadedChapters
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
