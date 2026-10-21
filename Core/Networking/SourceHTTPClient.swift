import Foundation

public protocol SourceHTTPClient: Sendable {
    func data(for request: SourceRequest, timeout: Duration) async throws -> (Data, URLResponse)
}

public final class URLSessionHTTPClient: SourceHTTPClient, @unchecked Sendable {
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .default) {
        self.session = URLSession(configuration: configuration)
    }

    public func data(for request: SourceRequest, timeout: Duration) async throws -> (Data, URLResponse) {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = timeout.timeInterval
        for (key, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: key) }
        return try await session.data(for: urlRequest)
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let value = components
        return TimeInterval(value.seconds) + TimeInterval(value.attoseconds) / 1_000_000_000_000_000_000
    }
}
