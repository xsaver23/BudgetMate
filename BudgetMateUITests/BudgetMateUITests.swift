import XCTest

final class BudgetMateUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchShowsAnUnauthenticatedEntryPointWithoutCloudCredentials() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.waitForExistence(timeout: 15))

        let intro = app.staticTexts["Welcome to BudgetMate"]
        let signIn = app.staticTexts["Welcome back"]
        XCTAssertTrue(
            intro.waitForExistence(timeout: 10) || signIn.waitForExistence(timeout: 10),
            "BudgetMate should show the intro or sign-in entry point when launched without a session."
        )
    }
}
