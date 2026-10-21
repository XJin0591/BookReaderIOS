import XCTest
@testable import BookReaderIOS

final class BookSourceImportTests: XCTestCase {
    func testDecodesSingleSourceAndPreservesHeadersCookieAndUnknownFields() throws {
        let data = Data("""
        {
          "bookSourceName": "示例书源",
          "bookSourceUrl": "https://example.invalid/source",
          "enabled": true,
          "searchUrl": "https://example.invalid/search?q={{key}}",
          "ruleSearch": {"bookList": ".book", "name": "h2"},
          "header": {"User-Agent": "BookReaderIOS"},
          "cookie": "sid=fixture",
          "customExtension": {"kind": "fixture"}
        }
        """.utf8)

        let sources = try BookSourceImport.decode(data)

        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources[0].bookSourceName, "示例书源")
        XCTAssertEqual(sources[0].requestHeaders["User-Agent"], "BookReaderIOS")
        XCTAssertEqual(sources[0].cookie, "sid=fixture")
        XCTAssertEqual(sources[0].additionalFields["customExtension"], .object(["kind": .string("fixture")]))
    }

    func testDecodesArrayAndRejectsMalformedOrUnsupportedRecords() throws {
        let data = Data("""
        [
          {"bookSourceName":"一","bookSourceUrl":"https://example.invalid/one"},
          {"bookSourceName":"二","bookSourceUrl":"https://example.invalid/two"}
        ]
        """.utf8)

        XCTAssertEqual(try BookSourceImport.decode(data).count, 2)
        XCTAssertThrowsError(try BookSourceImport.decode(Data("not-json".utf8)))
        XCTAssertThrowsError(try BookSourceImport.decode(Data("{\"bookSourceName\":\"缺少地址\"}".utf8)))
        XCTAssertThrowsError(try BookSourceImport.decode(Data("42".utf8)))
    }

    func testNormalizesDuplicateURLsAndDefaultsEnabled() throws {
        let data = Data("""
        [
          {"bookSourceName":"一","bookSourceUrl":"HTTPS://EXAMPLE.INVALID/source/"},
          {"bookSourceName":"二","bookSourceUrl":"https://example.invalid/source"}
        ]
        """.utf8)

        let sources = try BookSourceImport.decode(data)
        XCTAssertEqual(sources.count, 1)
        XCTAssertTrue(sources[0].enabled)
        XCTAssertEqual(sources[0].id, "https://example.invalid/source")
    }
}
