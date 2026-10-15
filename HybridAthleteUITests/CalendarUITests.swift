import XCTest

/// The Calendar tab and Session detail with the DEBUG seed plan and fake runs.
final class CalendarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMonthDayCardDetailAndBack() throws {
        let app = launch(today: "2026-10-28")
        let title = element(app, "calendar.monthTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "October 2026")
        XCTAssertTrue(app.buttons["calendarCell-2026-10-28"].isSelected)
        XCTAssertEqual(element(app, "dayCard.name").label, "Easy run")
        XCTAssertEqual(element(app, "dayCard.status").label, "Today")
        XCTAssertFalse(app.buttons["monthPrev"].isEnabled)
        keepScreenshot(of: app, named: "Calendar - October")

        // A day before the plan start does nothing.
        app.buttons["calendarCell-2026-10-05"].tap()
        XCTAssertTrue(app.buttons["calendarCell-2026-10-28"].isSelected)
        XCTAssertFalse(app.buttons["calendarCell-2026-10-05"].isEnabled)

        // Friday's long run is upcoming.
        app.buttons["calendarCell-2026-10-30"].tap()
        XCTAssertTrue(app.buttons["calendarCell-2026-10-30"].isSelected)
        XCTAssertEqual(element(app, "dayCard.name").label, "Long run")
        XCTAssertEqual(element(app, "dayCard.status").label, "Upcoming")

        // The arrow opens the detail, without the tab bar.
        app.buttons["sessionDetail"].tap()
        let detailTitle = element(app, "sessionDetailTitle")
        XCTAssertTrue(detailTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(detailTitle.label, "Long run")
        XCTAssertEqual(element(app, "sessionDetailWeek").label, "Week 3 of 8 · Base phase")
        // The template's long run has one numbered segment.
        XCTAssertTrue(element(app, "sessionSegment-1").label.hasPrefix("Segment 1, Long run"))
        XCTAssertFalse(app.buttons["tab.calendar"].exists)
        keepScreenshot(of: app, named: "Session detail - long run")

        // Back keeps the month and the selection.
        app.buttons["sessionDetailBack"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "October 2026")
        XCTAssertTrue(app.buttons["calendarCell-2026-10-30"].isSelected)
        XCTAssertTrue(app.buttons["tab.calendar"].exists)

        // Next month selects its first session day.
        app.buttons["monthNext"].tap()
        XCTAssertEqual(title.label, "November 2026")
        XCTAssertTrue(app.buttons["calendarCell-2026-11-02"].isSelected)
        keepScreenshot(of: app, named: "Calendar - November")
    }

    @MainActor
    func testACompletedSessionShowsTheRun() throws {
        let app = launch(today: "2026-10-28")
        XCTAssertTrue(element(app, "calendar.monthTitle").waitForExistence(timeout: 10))
        app.buttons["calendarCell-2026-10-26"].tap()
        XCTAssertEqual(element(app, "dayCard.status").label, "Completed")
        app.buttons["sessionDetail"].tap()
        XCTAssertTrue(element(app, "sessionDetailResult").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "sessionDetailResult").label.contains("Your run"))
        keepScreenshot(of: app, named: "Session detail - completed")
    }

    @MainActor
    func testBeforeThePlanSelectsTheFirstSession() throws {
        let app = launch(today: "2026-10-10")
        let title = element(app, "calendar.monthTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "October 2026")
        XCTAssertTrue(app.buttons["calendarCell-2026-10-12"].isSelected)
    }

    // MARK: Helpers

    @MainActor
    private func launch(today: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedPlan", "-fakeRuns", "-today", today, "-startTab", "calendar", "-planDelay", "0"]
        app.launch()
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
