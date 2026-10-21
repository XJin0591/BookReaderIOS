import Foundation

@MainActor
public protocol BookSourceStore: AnyObject {
    func all() throws -> [BookSource]
    func importSources(_ sources: [BookSource]) throws -> Int
    func initializeSeeds(_ sources: [BookSource], version: Int) throws -> Int
    func setEnabled(_ enabled: Bool, sourceID: String) throws
    func delete(sourceID: String) throws
}

@MainActor
public final class LocalBookSourceStore: BookSourceStore {
    private struct State: Codable {
        var sources: [BookSource] = []
        var deletedIDs: Set<String> = []
        var seedVersion: Int = 0
    }

    private let fileURL: URL
    private var state: State

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL) {
            self.state = try JSONDecoder().decode(State.self, from: data)
        } else {
            self.state = State()
        }
    }

    public func all() throws -> [BookSource] {
        state.sources
    }

    public func importSources(_ sources: [BookSource]) throws -> Int {
        var imported = 0
        for source in sources where !state.deletedIDs.contains(source.id) && !state.sources.contains(where: { $0.id == source.id }) {
            state.sources.append(source)
            imported += 1
        }
        try persist()
        return imported
    }

    public func initializeSeeds(_ sources: [BookSource], version: Int) throws -> Int {
        guard version > state.seedVersion else { return 0 }
        let count = try importSources(sources)
        state.seedVersion = version
        try persist()
        return count
    }

    public func setEnabled(_ enabled: Bool, sourceID: String) throws {
        guard let index = state.sources.firstIndex(where: { $0.id == BookSource.normalizeURL(sourceID) }) else { return }
        state.sources[index].enabled = enabled
        try persist()
    }

    public func delete(sourceID: String) throws {
        let normalized = BookSource.normalizeURL(sourceID)
        state.sources.removeAll { $0.id == normalized }
        state.deletedIDs.insert(normalized)
        try persist()
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}
