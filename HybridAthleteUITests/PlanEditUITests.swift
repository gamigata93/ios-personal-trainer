import XCTest

/// Moving, swapping, marking missed and undoing on the Calendar, with the DEBUG
/// seed plan (in an in-memory database) and fake runs on Wed 28 Oct 2026.
final class PlanEditUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMoveToNextDayAndUndo() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["calendarCell-2026-10-28"].isSelected)
        app.buttons["actionMoveNext"].tap()

        let notice = element(app, "noticeBar.text")
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertEqual(notice.label, "Moved Easy run to Thu 29 Oct.")
        XCTAssertTrue(app.buttons["calendarCell-2026-10-29"].isSelected)
        XCTAssertEqual(element(app, "dayCard.moved").label, "Moved from Wed 28 Oct")
        keepScreenshot(of: app, named: "Moved with notice")

        app.buttons["noticeUndo"].tap()
        XCTAssertTrue(notice.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["calendarCell-2026-10-28"].isSelected)
        XCTAssertFalse(element(app, "dayCard.moved").exists)
        XCTAssertEqual(element(app, "dayCard.status").label, "Today")
    }

    @MainActor
    func testSwapTwoSessions() throws {
        let app = launch()
        app.buttons["calendarCell-2026-10-30"].tap()
        app.buttons["actionSwap"].tap()

        let banner = element(app, "editBanner")
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertTrue(banner.label.contains("Swapping Long run. Tap an upcoming session to trade places."))
        // Every other cell is dimmed and ignores taps; today's session is a target.
        XCTAssertFalse(app.buttons["calendarCell-2026-10-29"].isEnabled)
        XCTAssertFalse(app.buttons["calendarCell-2026-10-26"].isEnabled)
        XCTAssertTrue(app.buttons["calendarCell-2026-10-28"].isEnabled)
        keepScreenshot(of: app, named: "Swap mode")

        app.buttons["calendarCell-2026-10-28"].tap()
        let notice = element(app, "noticeBar.text")
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertEqual(notice.label, "Swapped: Long run is now on Wed 28 Oct, Easy run on Fri 30 Oct.")
        XCTAssertFalse(banner.exists)
        XCTAssertTrue(app.buttons["calendarCell-2026-10-28"].isSelected)
        XCTAssertEqual(element(app, "dayCard.name").label, "Long run")
    }

    @MainActor
    func testMarkMissedShowsEverywhere() throws {
        let app = launch()
        app.buttons["calendarCell-2026-10-21"].tap()
        XCTAssertEqual(element(app, "dayCard.status").label, "Not recorded")
        app.buttons["actionMissed"].tap()

        XCTAssertTrue(element(app, "dayCard.status").waitForLabel("Missed", timeout: 5))
        XCTAssertTrue(app.buttons["calendarCell-2026-10-21"].label.contains("Easy run, missed"))
        XCTAssertEqual(element(app, "noticeBar.text").label, "Marked Easy run as missed.")
        keepScreenshot(of: app, named: "Missed")

        app.buttons["tab.home"].tap()
        XCTAssertTrue(element(app, "home.ring").waitForLabel("Plan adherence 86 percent", timeout: 10))
        app.buttons["weekPrev"].tap()
        XCTAssertTrue(app.buttons["home.day.2026-10-21"].label.contains("missed"))
        app.buttons["home.day.2026-10-21"].tap()
        XCTAssertEqual(element(app, "dayCard.status").label, "Missed")
    }

    @MainActor
    func testCancelChangesNothing() throws {
        let app = launch()
        app.buttons["actionMoveAnother"].tap()
        let banner = element(app, "editBanner")
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertTrue(banner.label.contains("Moving Easy run. Tap a free day, today or later."))
        XCTAssertTrue(app.buttons["calendarCell-2026-10-29"].isEnabled)
        XCTAssertFalse(app.buttons["calendarCell-2026-10-30"].isEnabled)

        app.buttons["editCancel"].tap()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["calendarCell-2026-10-28"].isSelected)
        XCTAssertEqual(element(app, "dayCard.status").label, "Today")
        XCTAssertFalse(element(app, "noticeBar").exists)
        XCTAssertFalse(element(app, "dayCard.moved").exists)
    }

    // MARK: Helpers

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedPlan", "-fakeRuns", "-today", "2026-10-28", "-startTab", "calendar", "-planDelay", "0"]
        app.launch()
        XCTAssertTrue(element(app, "calendar.monthTitle").waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    /// Waits for the label to change after an edit is saved.
    func waitForLabel(_ label: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: self)], timeout: timeout) == .completed
    }
}
