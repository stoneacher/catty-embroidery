// UI automation requires XCUITest; Swift Testing has no UI-testing support.
import XCTest

final class CatrobatEmbroideryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
    }
}
