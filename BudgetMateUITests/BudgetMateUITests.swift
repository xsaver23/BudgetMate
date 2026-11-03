import XCTest
import UIKit

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

        let settleUp = app.buttons["Settle up"].firstMatch
        scrollToHittable(settleUp, in: app)
        settleUp.tap()
        XCTAssertTrue(app.buttons["Mark as paid"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Mark as paid"].waitForNonExistence(timeout: 5))

        app.buttons["tab.transactions"].tap()
        XCTAssertTrue(app.buttons["tab.transactions"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Income"].waitForExistence(timeout: 5) ||
                app.staticTexts["Projected income"].waitForExistence(timeout: 5),
            "Transactions should identify whether income includes projected occurrences."
        )
        let roadTripGas = app.staticTexts["Road Trip Gas"]
        scrollToHittable(roadTripGas, in: app)
        XCTAssertTrue(
            roadTripGas.exists,
            "The synthetic fixture must render its seeded current-month transactions."
        )

        app.buttons["tab.budget"].tap()
        XCTAssertTrue(app.staticTexts["Category Budgets"].waitForExistence(timeout: 5))

        app.buttons["tab.settings"].tap()
        XCTAssertTrue(app.staticTexts["Currency"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sync"].waitForExistence(timeout: 5))

        let lightAppearance = app.segmentedControls.buttons["Light"]
        XCTAssertTrue(lightAppearance.waitForExistence(timeout: 5))
        lightAppearance.tap()
        XCTAssertTrue(lightAppearance.isSelected)
        XCTAssertFalse(
            app.staticTexts["Needs attention"].waitForExistence(timeout: 5),
            "Changing local appearance in the offline fixture must not attempt cloud sync."
        )

        let signOut = app.descendants(matching: .any)["settings.signOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        signOut.tap()
        let signOutWarning = app.staticTexts["You’ll be signed out of this device. Changes that have not synced may not be available after you sign in elsewhere."]
        XCTAssertTrue(signOutWarning.waitForExistence(timeout: 5))
        dismissConfirmationDialog(in: app)
        XCTAssertTrue(signOutWarning.waitForNonExistence(timeout: 5))

        let advancedSupport = app.buttons["Advanced & Support"]
        XCTAssertTrue(advancedSupport.waitForExistence(timeout: 5))
        advancedSupport.tap()
        let resetSettings = app.buttons["Reset Settings"].firstMatch
        scrollToHittable(resetSettings, in: app)
        resetSettings.tap()
        let resetWarning = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "This restores appearance and budget settings"))
            .firstMatch
        XCTAssertTrue(resetWarning.waitForExistence(timeout: 5))
        dismissConfirmationDialog(in: app)
        XCTAssertTrue(resetWarning.waitForNonExistence(timeout: 5))

        app.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["settings.privacyPolicy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["settings.support"].exists)

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
        XCTAssertTrue(app.staticTexts["Discard transaction?"].waitForExistence(timeout: 5))
        app.buttons["Discard Changes"].tap()
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
        XCTAssertTrue(
            app.staticTexts["Income"].waitForExistence(timeout: 5) ||
                app.staticTexts["Projected income"].waitForExistence(timeout: 5),
            "Transactions should identify whether income includes projected occurrences."
        )
        app.buttons["tab.budget"].tap()
        XCTAssertTrue(app.staticTexts["Category Budgets"].waitForExistence(timeout: 5))
        app.buttons["tab.settings"].tap()
        XCTAssertTrue(app.staticTexts["Currency"].waitForExistence(timeout: 5))

        app.staticTexts["2 members"].tap()
        XCTAssertTrue(app.staticTexts["Budget members"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Only the budget owner can invite members. Member removal is temporarily unavailable for everyone."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["budgetMembers.invitesUnavailable"].exists)
    }

    func testSyntheticFutureMonthProjectionLabelsReachableAtDefaultAndAX3() {
        for (name, accessibility3) in [("default", false), ("ax3", true)] {
            let app = launchSyntheticScenario(
                "-ui-testing-synthetic-owner",
                accessibility3: accessibility3
            )

            XCTAssertTrue(app.buttons["tab.dashboard"].waitForExistence(timeout: 15))
            let nextMonth = app.buttons["Next month"]
            XCTAssertTrue(nextMonth.waitForExistence(timeout: 5))
            nextMonth.tap()

            XCTAssertTrue(app.staticTexts["Projected income"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Projected expenses"].waitForExistence(timeout: 10))
            XCTAssertTrue(
                app.staticTexts
                    .matching(NSPredicate(format: "label BEGINSWITH %@", "Projected net"))
                    .firstMatch
                    .waitForExistence(timeout: 10)
            )
            XCTAssertTrue(app.staticTexts["Projected spend"].waitForExistence(timeout: 10))

            let projectedExpenses = app.staticTexts["Projected expenses"]
            scrollToHittable(projectedExpenses, in: app)
            let dashboardScreenshot = XCTAttachment(screenshot: app.screenshot())
            dashboardScreenshot.name = "future-projection-\(name)-dashboard"
            dashboardScreenshot.lifetime = .keepAlways
            add(dashboardScreenshot)

            app.buttons["tab.transactions"].tap()
            let upcoming = app.staticTexts["Upcoming"]
            XCTAssertTrue(upcoming.waitForExistence(timeout: 10))
            scrollToHittable(upcoming, in: app)
            XCTAssertTrue(app.staticTexts["Projected income"].waitForExistence(timeout: 10))
            XCTAssertTrue(
                app.staticTexts
                    .matching(NSPredicate(format: "label BEGINSWITH %@", "Projected net"))
                    .firstMatch
                    .waitForExistence(timeout: 10)
            )
            let transactionsScreenshot = XCTAttachment(screenshot: app.screenshot())
            transactionsScreenshot.name = "future-projection-\(name)-transactions"
            transactionsScreenshot.lifetime = .keepAlways
            add(transactionsScreenshot)

            app.buttons["tab.budget"].tap()
            let monthlyBudget = app.staticTexts["MONTHLY BUDGET"]
            XCTAssertTrue(monthlyBudget.waitForExistence(timeout: 10))
            scrollToHittable(monthlyBudget, in: app)
            let budgetScreenshot = XCTAttachment(screenshot: app.screenshot())
            budgetScreenshot.name = "future-projection-\(name)-budget"
            budgetScreenshot.lifetime = .keepAlways
            add(budgetScreenshot)
            app.terminate()
        }
    }

    private func launchSyntheticScenario(
        _ argument: String,
        accessibility3: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", argument]
        let contentSizeCategory = accessibility3
            ? UIContentSizeCategory.accessibilityExtraLarge.rawValue
            : UIContentSizeCategory.large.rawValue
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            contentSizeCategory
        ]
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

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func dismissConfirmationDialog(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
    }
}
