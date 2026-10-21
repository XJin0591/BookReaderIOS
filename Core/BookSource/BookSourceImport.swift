import Foundation

public enum BookSourceImportError: LocalizedError, Equatable {
    case invalidJSON(String)
    case invalidRecord(String)
    case unsupportedFormat

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let message): return "书源 JSON 无效：\(message)"
        case .invalidRecord(let message): return "书源记录无效：\(message)"
        case .unsupportedFormat: return "仅支持单个 Legado 书源对象或书源数组"
        }
    }
}

public enum BookSourceImport {
    public static func decode(_ data: Data) throws -> [BookSource] {
        let decoder = JSONDecoder()
        do {
            if let array = try? decoder.decode([BookSource].self, from: data) {
                return deduplicate(array)
            }
            if let source = try? decoder.decode(BookSource.self, from: data) {
                return [source]
            }
            throw BookSourceImportError.unsupportedFormat
        } catch let error as BookSourceImportError {
            throw error
        } catch {
            throw BookSourceImportError.invalidJSON(error.localizedDescription)
        }
    }

    private static func deduplicate(_ sources: [BookSource]) -> [BookSource] {
        var seen = Set<String>()
        return sources.filter { seen.insert($0.id).inserted }
    }
}
