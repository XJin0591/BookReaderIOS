import Combine
import Foundation

@MainActor
final class ChapterReaderViewModel: ObservableObject {
    @Published private(set) var content: ChapterContent?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service: LegadoBookService

    init(service: LegadoBookService = LegadoRemoteBookService()) {
        self.service = service
    }

    func load(chapter: BookChapter, source: BookSource) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            content = try await service.content(for: chapter, source: source)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
