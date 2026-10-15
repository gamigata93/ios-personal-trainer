import XCTest

/// The Sleep card on Home with the DEBUG seed plan, fake runs and a fake sleep
/// scenario on Wed 21 Oct 2026. The ready card is one VoiceOver element, so its
/// numbers are read from the card's accessibility label.
final class SleepUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNormalNight() throws {
        let app = launch(sleep: "normal")
        let card = sleepCard(app)
        XCTAssertTrue(card.waitForLabel(containing: "7 hours 30 minutes asleep", timeout: 10))
        XCTAssertTrue(card.label.contains("7 percent above your last 7 nights"))
        XCTAssertTrue(card.label.contains("Deep 1 hour 15 minutes, Core 4 hours 35 minutes, REM 1 hour 40 minutes"))
        app.swipeUp()
        keepScreenshot(of: app, named: "Sleep - normal")
    }

    @MainActor
    func testShortNight() throws {
        let app = launch(sleep: "short")
        let card = sleepCard(app)
        XCTAssertTrue(card.waitForLabel(containing: "6 hours 12 minutes asleep", timeout: 10))
        XCTAssertTrue(card.label.contains("14 percent below your last 7 nights"))
        app.swipeUp()
        keepScreenshot(of: app, named: "Sleep - short")
    }

    @MainActor
    func testNoSleepData() throws {
        let app = launch(sleep: "none")
        XCTAssertTrue(sleepCard(app).waitForLabel(containing: "No sleep data yet", timeout: 10))
        app.swipeUp()
        keepScreenshot(of: app, named: "Sleep - none")
    }

    @MainActor
    func testFailedReadOffersTryAgain() throws {
        let app = launch(sleep: "failed")
        XCTAssertTrue(app.buttons["sleepRetry"].waitForExistence(timeout: 10))
        app.swipeUp()
        keepScreenshot(of: app, named: "Sleep - failed")
    }

    // MARK: Helpers

    @MainActor
    private func launch(sleep scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedPlan", "-fakeRuns", "-today", "2026-10-21", "-planDelay", "0", "-fakeSleep", scenario]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["home.countdown"].firstMatch.waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func sleepCard(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["sleepCard"].firstMatch
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
    func waitForLabel(containing text: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: self)], timeout: timeout) == .completed
    }
}
