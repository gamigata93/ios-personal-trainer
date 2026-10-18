import XCTest

/// The workout breakdown and the coach's note with the DEBUG seed plan, fake
/// runs, fake workout detail and canned coach notes.
final class CoachNoteUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTempoBreakdownAndNote() throws {
        let app = launch(detail: "tempo", note: "ok")
        openSession(app, "2026-10-12")
        XCTAssertTrue(element(app, "workoutTiles").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "splitsChart").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "zonesCard").exists)
        for row in 0..<3 {
            let block = element(app, "planVsActualRow-\(row)")
            XCTAssertTrue(block.exists, "row \(row)")
            XCTAssertTrue(block.label.hasSuffix("On target"), block.label)
        }
        XCTAssertFalse(element(app, "planVsActualRow-3").exists)
        // 12 Oct is older than 7 days: the note is written on request.
        let write = app.buttons["coachNoteWrite"]
        if write.waitForExistence(timeout: 5) { write.tap() }
        let body = element(app, "coachNoteBody")
        XCTAssertTrue(body.waitForExistence(timeout: 10))
        for part in ["Steady and controlled", "How it went", "Versus the plan", "The program", "Next"] {
            XCTAssertTrue(body.label.contains(part), part)
        }
        keepScreenshot(of: app, named: "Session detail - tempo note")
        app.swipeUp()
        keepScreenshot(of: app, named: "Session detail - tempo charts")
        app.swipeUp()
        keepScreenshot(of: app, named: "Session detail - tempo plan vs actual")
    }

    @MainActor
    func testHomeShowsTheLatestNote() throws {
        let app = launch(detail: "tempo", note: "ok", tab: "home")
        let card = element(app, "latestCoachNote")
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.swipeUpUntilHittable(in: app)
        keepScreenshot(of: app, named: "Home - latest coach note")
        card.tap()
        XCTAssertTrue(element(app, "sessionDetailTitle").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "coachNoteBody").waitForExistence(timeout: 10))
    }

    @MainActor
    func testWithoutHeartRateTheZonesAreHidden() throws {
        let app = launch(detail: "noHr", note: "ok")
        openSession(app, "2026-10-12")
        XCTAssertTrue(element(app, "splitsChart").waitForExistence(timeout: 10))
        XCTAssertFalse(element(app, "zonesCard").exists)
        let footnote = element(app, "workoutFootnote")
        footnote.swipeUpUntilHittable(in: app)
        XCTAssertEqual(footnote.label, "No heart rate data for this run.")
    }

    @MainActor
    func testDriftIsInTheFactsAndWorthWatching() throws {
        let app = launch(detail: "easyDrift", note: "ok")
        // Fri 16 Oct: a 9.0 km long run; the fake runs 8.0 km with rising heart rate.
        openSession(app, "2026-10-16")
        let verdict = element(app, "sessionDetailVerdict")
        XCTAssertTrue(verdict.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForLabel(verdict, "Worth watching"))
        let menu = app.buttons["coachNoteMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        XCTAssertTrue(app.buttons["Copy facts"].waitForExistence(timeout: 5))
        // The runner may not read the clipboard, so the same facts are read from the DEBUG sheet.
        app.buttons["Show facts"].tap()
        let facts = element(app, "coachNoteFactsText")
        XCTAssertTrue(facts.waitForExistence(timeout: 5))
        XCTAssertTrue(facts.label.contains("Heart rate drift +12% (high) from the first to the last third."), facts.label)
    }

    @MainActor
    func testSlowShowsWritingThenTheNote() throws {
        let app = launch(detail: "tempo", note: "slow")
        openSession(app, "2026-10-12")
        let write = app.buttons["coachNoteWrite"]
        XCTAssertTrue(write.waitForExistence(timeout: 10))
        write.tap()
        XCTAssertTrue(element(app, "coachNoteWriting").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "coachNoteWriting").label, "Writing your note…")
        keepScreenshot(of: app, named: "Session detail - writing")
        XCTAssertTrue(element(app, "coachNoteBody").waitForExistence(timeout: 15))
    }

    @MainActor
    func testAFailureOffersTryAgain() throws {
        // The first note (26 Oct, written after the refresh) fails once.
        let app = launch(detail: "tempo", note: "fail")
        openSession(app, "2026-10-26")
        let retry = app.buttons["coachNoteTryAgain"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        XCTAssertTrue(element(app, "coachNoteFailed").exists)
        keepScreenshot(of: app, named: "Session detail - failed")
        retry.tap()
        XCTAssertTrue(element(app, "coachNoteBody").waitForExistence(timeout: 15))
    }

    @MainActor
    func testRulesSaysRulesInTheFooter() throws {
        let app = launch(detail: "tempo", note: "rules")
        openSession(app, "2026-10-26")
        let body = element(app, "coachNoteBody")
        XCTAssertTrue(body.waitForExistence(timeout: 15))
        XCTAssertTrue(body.label.contains("Written by rules"), body.label)
    }

    @MainActor
    func testTheLabRunsAWorkoutNote() throws {
        let app = launch(detail: "tempo", note: "ok", tab: "home")
        let debugMenu = app.buttons["home.debugMenu"]
        XCTAssertTrue(debugMenu.waitForExistence(timeout: 10))
        debugMenu.tap()
        app.buttons["Model Lab"].tap()
        let run = app.buttons["modelLabRun"]
        XCTAssertTrue(run.waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "modelLabCoachModel").label.hasPrefix("Coach notes use: "))
        run.tap()
        let level = element(app, "modelLabFactsLevel-1")
        XCTAssertTrue(level.waitForExistence(timeout: 15))
        XCTAssertEqual(level.label, "Facts level 0")
        keepScreenshot(of: app, named: "Model Lab - workout note")
    }

    @MainActor
    func testTheLabMarksFlatData() throws {
        for (detail, expectsChip) in [("tempoVaried", false), ("flat", true)] {
            let app = launch(detail: detail, note: "ok", tab: "home")
            let debugMenu = app.buttons["home.debugMenu"]
            XCTAssertTrue(debugMenu.waitForExistence(timeout: 10))
            debugMenu.tap()
            app.buttons["Model Lab"].tap()
            let run = app.buttons["modelLabRun"]
            XCTAssertTrue(run.waitForExistence(timeout: 10))
            run.tap()
            XCTAssertTrue(element(app, "modelLabFactsLevel-1").waitForExistence(timeout: 15), detail)
            XCTAssertEqual(element(app, "modelLabFlatData-1").exists, expectsChip, detail)
            if expectsChip { keepScreenshot(of: app, named: "Model Lab - flat data") }
            app.terminate()
        }
    }

    // MARK: Helpers

    @MainActor
    private func launch(detail: String, note: String, tab: String = "calendar") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-seedPlan", "-fakeRuns", "-today", "2026-10-28", "-fakeWorkoutDetail", detail, "-fakeCoachNote", note,
            "-planDelay", "0", "-startTab", tab,
        ]
        app.launch()
        return app
    }

    /// From the Calendar: select the day, then the day card's arrow.
    @MainActor
    private func openSession(_ app: XCUIApplication, _ date: String) {
        let cell = app.buttons["calendarCell-\(date)"]
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForLabel(cell, suffix: ", completed"))
        cell.tap()
        app.buttons["sessionDetail"].tap()
        XCTAssertTrue(element(app, "sessionDetailTitle").waitForExistence(timeout: 5))
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10) == .completed
    }

    private func waitForLabel(_ element: XCUIElement, suffix: String) -> Bool {
        let predicate = NSPredicate(format: "label ENDSWITH %@", suffix)
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

private extension XCUIElement {
    /// Swipes up until the element can be tapped (it sits below the fold).
    @MainActor
    func swipeUpUntilHittable(in app: XCUIApplication) {
        var swipes = 0
        while !(exists && isHittable) && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
    }
}
