import XCTest

/// The DEBUG Model Lab with canned model answers (`-fakeLLM`), opened from the
/// Home header's long-press menu.
final class ModelLabUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCoachNotePlanDraftAndRunAll() throws {
        let app = openLab(scenario: "ok")
        XCTAssertTrue(element(app, "modelLabAvailability").label.contains("Context size: 4096 tokens"))

        app.buttons["modelLabRun"].tap()
        let first = element(app, "modelLabResult-1")
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(first.label.hasPrefix("On-device, 1.2 s, in 312 · out 64 · cached 0"), first.label)
        XCTAssertTrue(first.label.contains("Workout note: "), first.label)
        keepScreenshot(of: app, named: "Model Lab - workout note")

        app.buttons["modelLabExperiment-planDraft"].tap()
        app.buttons["modelLabRun"].tap()
        let draft = element(app, "modelLabResult-2")
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        XCTAssertTrue(draft.label.contains("Plan draft with 8 weeks"), draft.label)
        XCTAssertTrue(draft.label.contains("Valid"))
        keepScreenshot(of: app, named: "Model Lab - plan draft")

        app.buttons["modelLabRunAll"].tap()
        XCTAssertTrue(element(app, "modelLabResult-6").waitForExistence(timeout: 20))
        XCTAssertTrue(element(app, "modelLabResult-6").label.hasPrefix("PCC deep"))
        XCTAssertFalse(element(app, "modelLabResult-7").exists)
        XCTAssertTrue(app.buttons["modelLabCopy"].firstMatch.exists)

        app.buttons["modelLabBack"].tap()
        XCTAssertTrue(element(app, "home.header").waitForExistence(timeout: 5))
    }

    @MainActor
    func testInvalidPlanShowsOneIssueInTheLab() throws {
        let app = openLab(scenario: "invalidPlan")
        app.buttons["modelLabExperiment-planDraft"].tap()
        app.buttons["modelLabRun"].tap()
        let card = element(app, "modelLabResult-1")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("1 issue"), card.label)
        XCTAssertTrue(card.label.contains("Week 1 uses Tuesday, which is not a training day."))
    }

    @MainActor
    func testInvalidPlanSucceedsInTheRealFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-useInMemoryStores", "-resetCache", "-authorized", "-planGenerator", "onDevice", "-fakeLLM", "invalidPlan"]
        app.launch()
        XCTAssertTrue(app.buttons["plan.fiveK"].waitForExistence(timeout: 10))
        app.buttons["startingPoint.customRace"].tap()
        let raceDay = app.buttons["raceSetup.raceDay"]
        XCTAssertTrue(raceDay.waitForExistence(timeout: 5))
        raceDay.tap()
        let done = app.buttons["raceSetup.datePickerDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        for day in ["monday", "wednesday", "friday"] {
            app.buttons["raceSetup.day.\(day)"].tap()
        }
        let distance = app.textFields["raceSetup.distance"]
        distance.tap()
        distance.typeText("10")
        app.buttons["raceSetup.keyboardDone"].tap()
        app.buttons["raceSetup.build"].tap()
        XCTAssertTrue(element(app, "home.countdown").waitForExistence(timeout: 15))
    }

    @MainActor
    func testUnavailableShowsTheAvailabilityMessage() throws {
        let app = openLab(scenario: "unavailable")
        XCTAssertTrue(element(app, "modelLabAvailability").label.contains("Not ready"))
        app.buttons["modelLabInput-sample"].tap()
        app.buttons["modelLabRun"].tap()
        let card = element(app, "modelLabResult-1")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("Apple Intelligence isn't ready."), card.label)
    }

    @MainActor
    func testQuotaShowsTheQuotaSentence() throws {
        let app = openLab(scenario: "quota")
        app.buttons["modelLabInput-sample"].tap()
        app.buttons["modelLabRun"].tap()
        let card = element(app, "modelLabResult-1")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("Today's Apple Intelligence limit was reached. It resets"), card.label)
    }

    // MARK: Helpers

    @MainActor
    private func openLab(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedPlan", "-fakeRuns", "-today", "2026-10-28", "-fakeLLM", scenario, "-planDelay", "0"]
        app.launch()
        let debugMenu = app.buttons["home.debugMenu"]
        XCTAssertTrue(debugMenu.waitForExistence(timeout: 10))
        debugMenu.tap()
        let menuItem = app.buttons["Model Lab"]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5))
        menuItem.tap()
        XCTAssertTrue(app.buttons["modelLabRun"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "modelLabAvailability").waitForExistence(timeout: 5))
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
