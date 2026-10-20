import XCTest

final class SourceSearchFlowUITests: XCTestCase {
    func testAppShowsSearchAndSourceManagementDestinations() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["搜索书籍"].exists)
        XCTAssertTrue(app.buttons["书源管理"].exists)
    }
}
