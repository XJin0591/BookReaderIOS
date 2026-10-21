import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let store: LocalBookSourceStore
    let searchCoordinator: SearchCoordinator
    @Published private(set) var sources: [BookSource] = []

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("BookReaderIOS/sources.json")
        self.store = (try? LocalBookSourceStore(fileURL: url)) ?? (try! LocalBookSourceStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("BookReaderIOS-sources.json")))
        self.searchCoordinator = SearchCoordinator()
        reload()
    }

    func reload() {
        sources = (try? store.all()) ?? []
    }

    func importSources(_ imported: [BookSource]) {
        _ = try? store.importSources(imported)
        reload()
    }

    func setEnabled(_ enabled: Bool, sourceID: String) {
        try? store.setEnabled(enabled, sourceID: sourceID)
        reload()
    }

    func delete(sourceID: String) {
        try? store.delete(sourceID: sourceID)
        reload()
    }
}
