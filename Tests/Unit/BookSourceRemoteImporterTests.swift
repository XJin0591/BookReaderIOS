import XCTest
@testable import BookReaderIOS

final class BookSourceRemoteImporterTests: XCTestCase {
    func testImportsSourcesFromHTTPURL() async throws {
        RemoteImportURLProtocol.statusCode = 200
        RemoteImportURLProtocol.body = Data(#"[{"bookSourceName":"远程书源","bookSourceUrl":"https://example.invalid/source"}]"#.utf8)
        let importer = makeImporter()

        let sources = try await importer.importSources(from: "https://example.invalid/subscription.json")

        XCTAssertEqual(sources.map(\.bookSourceName), ["远程书源"])
    }

    func testRejectsNonHTTPResponse() async {
        RemoteImportURLProtocol.statusCode = 503
        RemoteImportURLProtocol.body = Data()
        let importer = makeImporter()

        do {
            _ = try await importer.importSources(from: "https://example.invalid/subscription.json")
            XCTFail("Expected HTTP status error")
        } catch BookSourceRemoteImportError.httpStatus(503) {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsInvalidURL() async {
        let importer = makeImporter()

        do {
            _ = try await importer.importSources(from: "not a URL")
            XCTFail("Expected invalid URL error")
        } catch BookSourceRemoteImportError.invalidURL {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeImporter() -> BookSourceRemoteImporter {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteImportURLProtocol.self]
        return BookSourceRemoteImporter(client: URLSessionHTTPClient(configuration: configuration))
    }
}

private final class RemoteImportURLProtocol: URLProtocol {
    static var statusCode = 200
    static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(string: "https://example.invalid")!
        let response = HTTPURLResponse(url: url, statusCode: Self.statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
