import XCTest
@testable import BookReaderIOS

final class LegadoRuleParserTests: XCTestCase {
    func testExtractsCSSTextAndAttribute() throws {
        let html = RuleValue.string("<div class='book'><a href='/book/1'><h2>三国演义</h2></a></div>")
        XCTAssertEqual(try LegadoRuleParser.extract("css:.book::text", from: html).map(\.stringValue), ["三国演义"])
        XCTAssertEqual(try LegadoRuleParser.extract("css:.book@href", from: html).map(\.stringValue), ["/book/1"])
    }

    func testExtractsXPathText() throws {
        let html = RuleValue.string("<div class='book'><h2>三国演义</h2></div>")
        XCTAssertEqual(try LegadoRuleParser.extract("xpath://h2/text()", from: html).map(\.stringValue), ["三国演义"])
    }

    func testExtractsJSONPathAndRegex() throws {
        let json: RuleValue = .object(["books": .array([.object(["title": .string("一")]), .object(["title": .string("二")])])])
        XCTAssertEqual(try LegadoRuleParser.extract("json:$.books[*].title", from: json).map(\.stringValue), ["一", "二"])
        XCTAssertEqual(try LegadoRuleParser.extract("regex:书名：([^<]+)", from: .string("书名：测试书<end>")).map(\.stringValue), ["测试书"])
    }

    func testMalformedRuleReturnsEmptyOrThrowsDeterministically() throws {
        XCTAssertTrue(try LegadoRuleParser.extract("json:$.missing", from: .object([:])).isEmpty)
        XCTAssertThrowsError(try LegadoRuleParser.extract("regex:[", from: .string("fixture")))
    }
}

final class JavaScriptRuleRuntimeTests: XCTestCase {
    func testRuntimeReturnsValueAndDoesNotExposeFileOrKeychainBridges() async throws {
        let runtime = JavaScriptRuleRuntime()
        let value = try await runtime.evaluate("input.title + '!'", input: .object(["title": .string("书")]), timeout: .seconds(1))
        XCTAssertEqual(value.stringValue, "书!")
        let safe = try await runtime.evaluate("typeof require === 'undefined' && typeof keychain === 'undefined'", input: .null, timeout: .seconds(1))
        XCTAssertEqual(safe.boolValue, true)
    }

    func testRuntimeTimesOut() async {
        let runtime = JavaScriptRuleRuntime()
        do {
            _ = try await runtime.evaluate("while (true) {}", input: .null, timeout: .milliseconds(20))
            XCTFail("Expected timeout")
        } catch JavaScriptRuleRuntimeError.timedOut {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
