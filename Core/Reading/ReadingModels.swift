import Foundation

public struct BookDetail: Identifiable, Equatable, Sendable {
    public let id: String
    public let sourceID: String
    public let title: String
    public let author: String?
    public let intro: String?
    public let coverURL: String?
    public let detailURL: String
    public let tocURL: String

    public init(
        id: String,
        sourceID: String,
        title: String,
        author: String?,
        intro: String?,
        coverURL: String?,
        detailURL: String,
        tocURL: String
    ) {
        self.id = id
        self.sourceID = sourceID
        self.title = title
        self.author = author
        self.intro = intro
        self.coverURL = coverURL
        self.detailURL = detailURL
        self.tocURL = tocURL
    }
}

public struct BookChapter: Identifiable, Equatable, Sendable {
    public let id: String
    public let sourceID: String
    public let title: String
    public let url: String
    public let index: Int

    public init(id: String, sourceID: String, title: String, url: String, index: Int) {
        self.id = id
        self.sourceID = sourceID
        self.title = title
        self.url = url
        self.index = index
    }
}

public struct ChapterContent: Equatable, Sendable {
    public let chapter: BookChapter
    public let text: String

    public init(chapter: BookChapter, text: String) {
        self.chapter = chapter
        self.text = text
    }
}

public enum LegadoBookServiceStage: Equatable, Sendable {
    case detail
    case tableOfContents
    case content

    var displayName: String {
        switch self {
        case .detail: return "书籍详情"
        case .tableOfContents: return "章节目录"
        case .content: return "章节正文"
        }
    }
}

public enum LegadoBookServiceError: LocalizedError, Equatable, Sendable {
    case invalidURL(stage: LegadoBookServiceStage, value: String)
    case invalidResponse(stage: LegadoBookServiceStage)
    case httpStatus(stage: LegadoBookServiceStage, statusCode: Int)
    case emptyRule(stage: LegadoBookServiceStage, field: String)
    case invalidRule(stage: LegadoBookServiceStage, field: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let stage, let value):
            return "\(stage.displayName)地址无效：\(value)"
        case .invalidResponse(let stage):
            return "\(stage.displayName)响应无效"
        case .httpStatus(let stage, let statusCode):
            return "\(stage.displayName)请求失败：HTTP \(statusCode)"
        case .emptyRule(let stage, let field):
            return "\(stage.displayName)规则“\(field)”没有匹配到内容"
        case .invalidRule(let stage, let field):
            return "\(stage.displayName)规则“\(field)”无法解析"
        }
    }
}
