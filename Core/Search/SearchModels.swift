import Foundation

public struct SearchBook: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let author: String?
    public let detailURL: String?
    public var sourceIDs: [String]
    public var detailURLsBySource: [String: String]

    public init(id: String, title: String, author: String?, detailURL: String?, sourceIDs: [String], detailURLsBySource: [String: String] = [:]) {
        self.id = id
        self.title = title
        self.author = author
        self.detailURL = detailURL
        self.sourceIDs = sourceIDs
        self.detailURLsBySource = detailURLsBySource.isEmpty
            ? Dictionary(uniqueKeysWithValues: sourceIDs.compactMap { sourceID in detailURL.map { (sourceID, $0) } })
            : detailURLsBySource
    }
}

public struct SourceSearchOutcome: Identifiable, Equatable, Sendable {
    public let id: String
    public let sourceName: String
    public let status: Status
    public let books: [SearchBook]

    public enum Status: Equatable, Sendable {
        case found(Int)
        case empty
        case failed(String)
        case timedOut
    }
}

public enum SourceSearchError: LocalizedError, Equatable {
    case failed(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        case .timedOut: return "书源请求超时"
        }
    }
}
