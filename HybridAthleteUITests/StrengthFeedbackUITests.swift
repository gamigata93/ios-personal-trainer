import XCTest

/// Strength sessions and the after-workout popup on the seed plan, Wed 28 Oct 2026.
/// -fakeRuns gives a run on Mon 26 Oct (asked about) and strength workouts on 14 and 21 Oct.
final class StrengthFeedbackUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testStrengthRowOpensTheExercises() throws {
        let app = launch()
        let row = app.buttons["strengthRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.hasPrefix("Strength: Lower body B, 30 min · 5 exercises, today"), row.label)
        row.tap()
        let title = element(app, "strengthDetailTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Strength: Lower body B")
        XCTAssertTrue(element(app, "strengthExercise-0").exists)
        XCTAssertTrue(element(app, "strengthExercise-4").exists)
        keepScreenshot(of: app, named: "Strength detail")
        app.buttons["strengthDetailBack"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    @MainActor
    func testACompletedStrengthDayInTheCalendar() throws {
        let app = launch(extra: ["-startTab", "calendar"])
        let cell = app.buttons["calendarCell-2026-10-21"]
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForLabel(cell, contains: "plus Strength: Calves and feet A, completed"), cell.label)
        cell.tap()
        let row = app.buttons["strengthRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("completed"), row.label)
    }

    @MainActor
    func testNoIssuesClosesThePopup() throws {
        let app = launch(extra: ["-feedbackPopup"])
        let sheet = element(app, "feedbackSheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        app.buttons["feedbackNo"].tap()
        app.buttons["feedbackSave"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertFalse(element(app, "suggestionCard").exists)
    }

    @MainActor
    func testPainSuggestsAChangeAndApplyThenUndo() throws {
        let app = launch(extra: ["-feedbackPopup"])
        XCTAssertTrue(element(app, "feedbackSheet").waitForExistence(timeout: 10))
        app.buttons["feedbackYes"].tap()
        app.buttons["feedbackArea-knee"].tap()
        app.buttons["feedbackSide-knee-left"].tap()
        app.buttons["feedbackKind-knee-pain"].tap()
        app.buttons["feedbackLevel-knee-2"].tap()
        keepScreenshot(of: app, named: "Feedback popup")
        app.buttons["feedbackSave"].tap()

        let reason = element(app, "suggestionReason")
        XCTAssertTrue(reason.waitForExistence(timeout: 10))
        XCTAssertTrue(reason.label.hasPrefix("Because of the pain, left knee, moderate"), reason.label)
        XCTAssertTrue(element(app, "suggestionChange-2026-10-30").exists)
        keepScreenshot(of: app, named: "Suggested change")
        app.buttons["suggestionApply"].tap()
        XCTAssertTrue(element(app, "suggestionApplied").waitForExistence(timeout: 5))
        // Today's strength became mobility.
        let row = app.buttons["strengthRow"]
        XCTAssertTrue(waitForLabel(row, contains: "Strength: Mobility A"), row.label)
        app.buttons["suggestionUndo"].tap()
        XCTAssertTrue(waitForLabel(row, contains: "Strength: Lower body B"), row.label)
    }

    @MainActor
    func testACannedModelWritesTheSuggestion() throws {
        let app = launch(extra: ["-feedbackPopup", "-fakeAdjust", "ok"])
        XCTAssertTrue(element(app, "feedbackSheet").waitForExistence(timeout: 10))
        app.buttons["feedbackYes"].tap()
        app.buttons["feedbackArea-calf"].tap()
        app.buttons["feedbackSide-calf-both"].tap()
        app.buttons["feedbackKind-calf-ache"].tap()
        app.buttons["feedbackLevel-calf-3"].tap()
        app.buttons["feedbackSave"].tap()
        let reason = element(app, "suggestionReason")
        XCTAssertTrue(reason.waitForExistence(timeout: 10))
        XCTAssertEqual(reason.label, "Fake: easier days while it settles.")
        app.buttons["suggestionKeep"].tap()
        XCTAssertTrue(element(app, "suggestionCard").waitForNonExistence(timeout: 5))
    }

    // MARK: Helpers

    @MainActor
    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedPlan", "-fakeRuns", "-today", "2026-10-28", "-planDelay", "0"] + extra
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, contains text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10) == .completed
    }

    @MainActor
    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
