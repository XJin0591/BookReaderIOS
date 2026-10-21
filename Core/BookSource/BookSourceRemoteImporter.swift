import Foundation

public enum BookSourceRemoteImportError: LocalizedError, Equatable, Sendable {
    case invalidURL(String)
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let value): return "订阅地址无效：\(value)"
        case .httpStatus(let status): return "订阅请求失败：HTTP \(status)"
        }
    }
}

public struct BookSourceRemoteImporter: Sendable {
    private let client: SourceHTTPClient
    private let timeout: Duration

    public init(client: SourceHTTPClient = URLSessionHTTPClient(), timeout: Duration = .seconds(15)) {
        self.client = client
        self.timeout = timeout
    }

    public func importSources(from value: String) async throws -> [BookSource] {
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: input),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw BookSourceRemoteImportError.invalidURL(input)
        }

        let request = SourceRequest(
            url: url,
            method: "GET",
            headers: [
                "Accept": "application/json",
                "User-Agent": "BookReaderIOS"
            ],
            body: nil
        )
        let (data, response) = try await client.data(for: request, timeout: timeout)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BookSourceRemoteImportError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try BookSourceImport.decode(data)
    }
}
