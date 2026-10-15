import XCTest

/// The HRV and resting heart rate cards on Home with the DEBUG seed plan, fake
/// runs, `-fakeSleep normal` and a `-fakeRecovery` scenario on Wed 21 Oct 2026.
/// Each ready card is one VoiceOver element, so its numbers are read from the
/// card's accessibility label ("58 milliseconds, 6 percent below...").
final class RecoveryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMock() throws {
        let app = launch(recovery: "mock")
        XCTAssertTrue(card(app, "hrvCard").waitForLabel(containing: "58 milliseconds, 6 percent below your last 7 nights", timeout: 10))
        XCTAssertTrue(card(app, "restingHrCard").waitForLabel(containing: "49 beats per minute, about the same as your last 7 days", timeout: 10))
        app.swipeUp()
        keepScreenshot(of: app, named: "Recovery - mock")
    }

    @MainActor
    func testGood() throws {
        let app = launch(recovery: "good")
        XCTAssertTrue(card(app, "hrvCard").waitForLabel(containing: "66 milliseconds, 7 percent above", timeout: 10))
        XCTAssertTrue(card(app, "restingHrCard").waitForLabel(containing: "48 beats per minute, 3 beats per minute below", timeout: 10))
        app.swipeUp()
        keepScreenshot(of: app, named: "Recovery - good")
    }

    @MainActor
    func testStrained() throws {
        let app = launch(recovery: "strained")
        XCTAssertTrue(card(app, "hrvCard").waitForLabel(containing: "45 milliseconds, 27 percent below", timeout: 10))
        XCTAssertTrue(card(app, "restingHrCard").waitForLabel(containing: "54 beats per minute, 3 beats per minute above", timeout: 10))
        app.swipeUp()
        keepScreenshot(of: app, named: "Recovery - strained")
    }

    @MainActor
    func testNoHrvKeepsRestingHeartRate() throws {
        let app = launch(recovery: "noHrv")
        XCTAssertTrue(card(app, "hrvCard").waitForLabel(containing: "No overnight HRV yet", timeout: 10))
        XCTAssertTrue(card(app, "restingHrCard").waitForLabel(containing: "49 beats per minute", timeout: 10))
        app.swipeUp()
        keepScreenshot(of: app, named: "Recovery - noHrv")
    }

    @MainActor
    func testFailedOffersTryAgainOnBoth() throws {
        let app = launch(recovery: "failed")
        XCTAssertTrue(app.buttons["hrvRetry"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["restingHrRetry"].waitForExistence(timeout: 10))
        app.swipeUp()
        keepScreenshot(of: app, named: "Recovery - failed")
    }

    // MARK: Helpers

    @MainActor
    private func launch(recovery scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-seedPlan", "-fakeRuns", "-fakeSleep", "normal", "-today", "2026-10-21", "-planDelay", "0",
            "-fakeRecovery", scenario,
        ]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["home.countdown"].firstMatch.waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func card(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
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
    func waitForLabel(containing text: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: self)], timeout: timeout) == .completed
    }
}
