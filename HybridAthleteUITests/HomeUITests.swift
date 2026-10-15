import XCTest

/// Home with the DEBUG seed plan and fake runs on Wed 28 Oct 2026. Launch
/// arguments are the DEBUG options in CompositionRoot.DebugOptions.
final class HomeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMidPlanHomeAndNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedPlan", "-fakeRuns", "-today", "2026-10-28", "-planDelay", "0"]
        app.launch()

        let countdown = element(app, "home.countdown")
        XCTAssertTrue(countdown.waitForExistence(timeout: 10))
        XCTAssertEqual(countdown.label, "39 days to go")
        let ring = element(app, "home.ring")
        XCTAssertTrue(ring.waitForLabel("Plan adherence 86 percent", timeout: 10))
        XCTAssertEqual(element(app, "home.weekCaption").label, "Week 3 of 8")
        XCTAssertTrue(app.buttons["home.day.2026-10-28"].isSelected)
        keepScreenshot(of: app, named: "Home - 28 Oct")

        // Friday's long run is upcoming.
        app.buttons["home.day.2026-10-30"].tap()
        XCTAssertTrue(app.buttons["home.day.2026-10-30"].isSelected)
        XCTAssertEqual(element(app, "dayCard.name").label, "Long run")
        XCTAssertEqual(element(app, "dayCard.status").label, "Upcoming")

        // The arrow opens the session detail, which hides the tab bar.
        app.buttons["sessionDetail"].tap()
        XCTAssertTrue(element(app, "sessionDetailTitle").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "sessionDetailTitle").label, "Long run")
        XCTAssertFalse(app.buttons["tab.calendar"].exists)
        keepScreenshot(of: app, named: "Session detail from Home")
        app.buttons["sessionDetailBack"].tap()
        XCTAssertTrue(countdown.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.day.2026-10-30"].isSelected)

        // The whole Up next card opens the next session.
        app.buttons["upNextCard"].tap()
        XCTAssertTrue(element(app, "sessionDetailTitle").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "sessionDetailTitle").label, "Long run")
        XCTAssertFalse(app.buttons["tab.home"].exists)
        app.buttons["sessionDetailBack"].tap()
        XCTAssertTrue(countdown.waitForExistence(timeout: 5))

        // Next week.
        app.buttons["weekNext"].tap()
        XCTAssertEqual(element(app, "home.weekRange").label, "2 - 8 Nov")
        XCTAssertTrue(app.buttons["home.day.2026-11-02"].isSelected)

        // The Calendar tab opens on the month holding today.
        app.buttons["tab.calendar"].tap()
        XCTAssertTrue(element(app, "calendar.monthTitle").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "calendar.monthTitle").label, "October 2026")
        app.buttons["tab.home"].tap()
        XCTAssertTrue(countdown.waitForExistence(timeout: 5))
    }

    @MainActor
    func testBeforeThePlanStarts() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedPlan", "-today", "2026-10-10"]
        app.launch()

        XCTAssertTrue(element(app, "home.countdown").waitForExistence(timeout: 10))
        XCTAssertEqual(element(app, "home.countdown").label, "57 days to go")
        XCTAssertEqual(element(app, "home.phase").label, "Starts Mon 12 Oct")
        XCTAssertEqual(element(app, "home.ring").label, "Plan has not started")
        XCTAssertTrue(app.buttons["home.day.2026-10-12"].isSelected)
        XCTAssertFalse(app.buttons["weekPrev"].isEnabled)
        keepScreenshot(of: app, named: "Home - before start")
    }

    // MARK: Helpers

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
    /// Waits for the label to change, e.g. once Health has been read.
    func waitForLabel(_ label: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: self)], timeout: timeout) == .completed
    }
}
