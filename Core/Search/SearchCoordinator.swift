import Combine
import Foundation

@MainActor
public final class SearchCoordinator: ObservableObject {
    @Published public private(set) var books: [SearchBook] = []
    @Published public private(set) var outcomes: [SourceSearchOutcome] = []

    private let service: SourceSearchService
    private let maxConcurrency: Int
    private var activeTask: Task<Void, Never>?

    public init(service: SourceSearchService = LegadoSourceSearchService(), maxConcurrency: Int = 4) {
        self.service = service
        self.maxConcurrency = max(1, maxConcurrency)
    }

    public func search(_ keyword: String, sources: [BookSource]) async {
        cancel()
        books = []
        outcomes = []
        let candidates = sources.filter { $0.enabled && ($0.searchURL != nil || !$0.ruleSearch.isEmpty) }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.run(keyword: keyword, sources: candidates)
        }
        activeTask = task
        await task.value
        activeTask = nil
    }

    public func cancel() {
        activeTask?.cancel()
        activeTask = nil
    }

    private func run(keyword: String, sources: [BookSource]) async {
        var nextIndex = 0
        let service = self.service
        await withTaskGroup(of: SourceSearchResult.self) { group in
            while nextIndex < sources.count && nextIndex < maxConcurrency {
                let source = sources[nextIndex]
                group.addTask {
                    do { return SourceSearchResult(source: source, result: .success(try await service.search(source: source, keyword: keyword))) }
                    catch { return SourceSearchResult(source: source, result: .failure(sourceSearchFailure(from: error))) }
                }
                nextIndex += 1
            }
            while let result = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                handle(result, keyword: keyword)
                if nextIndex < sources.count {
                    let source = sources[nextIndex]
                    group.addTask {
                        do { return SourceSearchResult(source: source, result: .success(try await service.search(source: source, keyword: keyword))) }
                        catch { return SourceSearchResult(source: source, result: .failure(sourceSearchFailure(from: error))) }
                    }
                    nextIndex += 1
                }
            }
        }
    }

    private func handle(_ result: SourceSearchResult, keyword: String) {
        let outcome: SourceSearchOutcome
        switch result.result {
        case .success(let sourceBooks):
            outcome = SourceSearchOutcome(id: result.source.id, sourceName: result.source.bookSourceName, status: sourceBooks.isEmpty ? .empty : .found(sourceBooks.count), books: sourceBooks)
            merge(sourceBooks, keyword: keyword)
        case .failure(let error):
            outcome = SourceSearchOutcome(id: result.source.id, sourceName: result.source.bookSourceName, status: error.status, books: [])
        }
        outcomes.append(outcome)
    }

    private func merge(_ incoming: [SearchBook], keyword: String) {
        for book in incoming {
            let key = normalize(book.title) + "|" + normalize(book.author ?? "")
            if let index = books.firstIndex(where: { normalize($0.title) + "|" + normalize($0.author ?? "") == key }) {
                books[index].sourceIDs.append(contentsOf: book.sourceIDs.filter { !books[index].sourceIDs.contains($0) })
                books[index].detailURLsBySource.merge(book.detailURLsBySource) { old, _ in old }
            } else {
                books.append(book)
            }
        }
        let normalizedKeyword = normalize(keyword)
        books.sort {
            let leftExact = normalize($0.title) == normalizedKeyword
            let rightExact = normalize($1.title) == normalizedKeyword
            if leftExact != rightExact { return leftExact && !rightExact }
            return $0.id < $1.id
        }
    }

    private func normalize(_ value: String) -> String {
        value.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
    }

}

private func sourceSearchFailure(from error: Error) -> SourceSearchFailure {
    if let error = error as? SourceSearchError {
        switch error {
        case .timedOut: return .timedOut
        case .failed(let message): return .failed(message)
        }
    }
    return .failed(error.localizedDescription)
}

private enum SourceSearchFailure: Error, Sendable {
    case failed(String)
    case timedOut

    var status: SourceSearchOutcome.Status {
        switch self {
        case .failed(let message): return .failed(message)
        case .timedOut: return .timedOut
        }
    }
}

private struct SourceSearchResult: Sendable {
    let source: BookSource
    let result: Result<[SearchBook], SourceSearchFailure>
}
