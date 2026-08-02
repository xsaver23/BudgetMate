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

    func testPersistenceFailureShowsAccessibleRecoverySurface() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-persistence-failure"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["BudgetMate needs help opening local data"].waitForExistence(timeout: 15)
        )
        XCTAssertTrue(app.buttons["Retry"].exists)
        XCTAssertTrue(app.buttons["Create Support Archive"].exists)
        XCTAssertTrue(app.buttons["Restore Archive"].exists)
        XCTAssertTrue(app.buttons["Reset Local Cache"].exists)
        XCTAssertFalse(app.buttons["Reset Local Cache"].isEnabled)
    }

    func testSyntheticOwnerNavigatesCoreScreensAndDismissesDatePicker() {
        let app = launchSyntheticScenario("-ui-testing-synthetic-owner")

        XCTAssertTrue(app.buttons["tab.dashboard"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Budget pacing"].waitForExistence(timeout: 5))

        app.buttons["tab.transactions"].tap()
        XCTAssertTrue(app.buttons["tab.transactions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Income"].waitForExistence(timeout: 5))

        app.buttons["tab.budget"].tap()
        XCTAssertTrue(app.staticTexts["Category Budgets"].waitForExistence(timeout: 5))

        app.buttons["tab.settings"].tap()
        XCTAssertTrue(app.staticTexts["Currency"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sync"].waitForExistence(timeout: 5))

        app.buttons["Add Transaction"].tap()
        XCTAssertTrue(app.buttons["transactionEditor.date"].waitForExistence(timeout: 5))
        app.buttons["transactionEditor.date"].tap()
        XCTAssertTrue(app.staticTexts["Transaction Date"].waitForExistence(timeout: 5))
        tapDifferentSyntheticDate(in: app)
        XCTAssertTrue(
            app.staticTexts["Transaction Date"].waitForNonExistence(timeout: 5),
            "Choosing a different graphical date should dismiss the date sheet."
        )
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["tab.dashboard"].waitForExistence(timeout: 5))

        app.buttons["tab.settings"].tap()
        app.staticTexts["2 members"].tap()
        XCTAssertTrue(app.staticTexts["Budget members"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["budgetMembers.invitesUnavailable"].exists)
        XCTAssertFalse(app.staticTexts["Only the budget owner can invite members. Member removal is temporarily unavailable for everyone."].exists)
    }

    func testSyntheticMemberNavigatesCoreScreensAndShowsReadOnlyMemberSettings() {
        let app = launchSyntheticScenario("-ui-testing-synthetic-member")

        XCTAssertTrue(app.buttons["tab.dashboard"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Budget pacing"].waitForExistence(timeout: 5))

        app.buttons["tab.transactions"].tap()
        XCTAssertTrue(app.staticTexts["Income"].waitForExistence(timeout: 5))
        app.buttons["tab.budget"].tap()
        XCTAssertTrue(app.staticTexts["Category Budgets"].waitForExistence(timeout: 5))
        app.buttons["tab.settings"].tap()
        XCTAssertTrue(app.staticTexts["Currency"].waitForExistence(timeout: 5))

        app.staticTexts["2 members"].tap()
        XCTAssertTrue(app.staticTexts["Budget members"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Only the budget owner can invite members. Member removal is temporarily unavailable for everyone."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["budgetMembers.invitesUnavailable"].exists)
    }

    private func launchSyntheticScenario(_ argument: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", argument]
        app.launch()
        return app
    }

    private func tapDifferentSyntheticDate(in app: XCUIApplication) {
        let datePicker = app.datePickers.element(boundBy: 0)
        XCTAssertTrue(datePicker.waitForExistence(timeout: 5))

        let calendar = Calendar.current
        let today = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let tomorrowLabel = tomorrow.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        let tomorrowShortLabel = tomorrow.formatted(.dateTime.month(.wide).day())
        let target = datePicker.buttons.allElementsBoundByIndex.first { button in
            let label = button.label
            return button.isHittable &&
                !label.localizedCaseInsensitiveContains("previous") &&
                !label.localizedCaseInsensitiveContains("next") &&
                (label.localizedCaseInsensitiveContains(tomorrowLabel) ||
                    label.localizedCaseInsensitiveContains(tomorrowShortLabel))
        }

        if let target {
            target.tap()
            return
        }

        // If tomorrow is outside the visible month, a visible date near the
        // end of the calendar is still guaranteed to differ from today's date
        // for this synthetic editor launch.
        let fallback = datePicker.buttons.allElementsBoundByIndex.reversed().first { button in
            let label = button.label
            return button.isHittable &&
                !label.localizedCaseInsensitiveContains("previous") &&
                !label.localizedCaseInsensitiveContains("next") &&
                !label.localizedCaseInsensitiveContains("month")
        }
        XCTAssertNotNil(fallback, "The graphical calendar should expose a selectable date.")
        fallback?.tap()
    }
}
