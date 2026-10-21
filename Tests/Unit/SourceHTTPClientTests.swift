import XCTest
@testable import BookReaderIOS

final class SourceHTTPClientTests: XCTestCase {
    func testRequestInterpolationEscapesQueryAndPreservesHeadersAndBody() throws {
        let request = try SourceRequest(
            urlTemplate: "https://example.invalid/search?q={{key}}&page={{page}}",
            method: "POST",
            headers: ["X-Test": "fixture"],
            bodyTemplate: "key={{key}}",
            values: ["key": "三国 演义", "page": "1"]
        )

        XCTAssertEqual(request.url.absoluteString, "https://example.invalid/search?q=%E4%B8%89%E5%9B%BD%20%E6%BC%94%E4%B9%89&page=1")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.headers["X-Test"], "fixture")
        XCTAssertEqual(String(data: try XCTUnwrap(request.body), encoding: .utf8), "key=三国 演义")
    }

    func testRejectsInvalidURLTemplate() {
        XCTAssertThrowsError(try SourceRequest(urlTemplate: "not a url", method: "GET", headers: [:], bodyTemplate: nil, values: [:]))
    }
}

final class URLSessionHTTPClientTests: XCTestCase {
    func testHTTPClientUsesURLProtocolAndCancellation() async throws {
        URLProtocol.registerClass(FixtureURLProtocol.self)
        defer { URLProtocol.unregisterClass(FixtureURLProtocol.self) }
        FixtureURLProtocol.responseData = Data("ok".utf8)
        FixtureURLProtocol.response = HTTPURLResponse(url: URL(string: "https://example.invalid")!, statusCode: 200, httpVersion: nil, headerFields: nil)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let client = URLSessionHTTPClient(configuration: configuration)
        let request = SourceRequest(url: URL(string: "https://example.invalid")!, method: "GET", headers: [:], body: nil)
        let result = try await client.data(for: request, timeout: .seconds(2))
        XCTAssertEqual(result.0, Data("ok".utf8))

        FixtureURLProtocol.delay = true
        let task = Task { try await client.data(for: request, timeout: .seconds(30)) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancellation should throw")
        } catch is CancellationError {
        } catch {
            XCTAssertTrue((error as NSError).code == NSURLErrorCancelled)
        }
        FixtureURLProtocol.delay = false
    }
}

private final class FixtureURLProtocol: URLProtocol {
    static var responseData = Data()
    static var response: HTTPURLResponse?
    static var delay = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if Self.delay { return }
        if let response = Self.response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
