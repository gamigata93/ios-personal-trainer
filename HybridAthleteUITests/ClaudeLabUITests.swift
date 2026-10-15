import XCTest

/// Claude in the DEBUG Model Lab with canned answers (`-fakeLLM`), an in-memory
/// ledger, settings and secret store. Nothing reaches the network or the Keychain.
final class ClaudeLabUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSonnetPlanDraftAndHaikuNoteAreCosted() throws {
        let app = openLab(scenario: "anthropicOk")
        app.buttons["modelLabModel-anthropic.sonnet55"].tap()
        XCTAssertEqual(element(app, "modelLabPriceLine").label, "$2 in · $10 out per 1M tokens")
        app.buttons["modelLabExperiment-planDraft"].tap()

        // The first Claude run asks for consent; without a key it explains what is missing.
        app.buttons["modelLabRun"].tap()
        allowClaude(app)
        let noKey = element(app, "modelLabResult-1")
        XCTAssertTrue(noKey.waitForExistence(timeout: 10))
        XCTAssertTrue(noKey.label.contains("Add your Anthropic API key to run Claude models."), noKey.label)

        saveKey(app, "sk-ant-fake-a1b2")
        XCTAssertEqual(element(app, "anthropicKeyStatus").label, "Saved · ends \u{2026}a1b2")
        app.buttons["modelLabRun"].tap()
        let draft = element(app, "modelLabResult-2")
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        XCTAssertTrue(draft.label.contains("cost $0.028"), draft.label)
        XCTAssertEqual(element(app, "modelLabCost-2").label, "$0.028")
        XCTAssertEqual(element(app, "costTotal").value as? String, "$0.028")
        app.segmentedControls["costPeriod"].buttons["All time"].tap()
        XCTAssertTrue(element(app, "costTotal").waitForValue("$0.028", timeout: 5))
        keepScreenshot(of: app, named: "Claude - plan draft costed")

        app.buttons["modelLabModel-anthropic.haiku55"].tap()
        app.buttons["modelLabExperiment-coachNote"].tap()
        app.buttons["modelLabInput-sample"].tap()
        app.buttons["modelLabRun"].tap()
        XCTAssertTrue(element(app, "modelLabResult-3").waitForExistence(timeout: 10))
        let haikuRow = element(app, "costModelRow-claude-haiku-5-5")
        XCTAssertTrue(haikuRow.waitForExistence(timeout: 5))
        XCTAssertTrue(haikuRow.label.contains("$0.0001"), haikuRow.label)
        XCTAssertTrue(element(app, "costModelRow-claude-sonnet-5-5").label.contains("$0.028"))
        keepScreenshot(of: app, named: "Claude - cost card")
    }

    @MainActor
    func testNoKeyShowsTheKeyMessage() throws {
        let app = openLab(scenario: "noKey")
        app.buttons["modelLabModel-anthropic.sonnet55"].tap()
        XCTAssertTrue(element(app, "modelLabAvailability").label.contains("Add your Anthropic API key to run Claude models."))
        app.buttons["modelLabInput-sample"].tap()
        app.buttons["modelLabRun"].tap()
        allowClaude(app)
        let card = element(app, "modelLabResult-1")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("Add your Anthropic API key to run Claude models."), card.label)
    }

    @MainActor
    func testCreditsShowsTheCreditMessage() throws {
        let app = openLab(scenario: "credits")
        app.buttons["modelLabModel-anthropic.sonnet55"].tap()
        saveKey(app, "sk-ant-fake-c3d4")
        app.buttons["modelLabInput-sample"].tap()
        app.buttons["modelLabRun"].tap()
        allowClaude(app)
        let card = element(app, "modelLabResult-1")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("Your Anthropic credit balance is too low. Add credits in the Claude Console."), card.label)
    }

    @MainActor
    func testPerRunCapBlocksFable() throws {
        let app = openLab(scenario: "anthropicOk")
        app.buttons["modelLabModel-anthropic.fable51"].tap()
        saveKey(app, "sk-ant-fake-e5f6")
        let perRun = app.textFields["capPerRun"]
        XCTAssertEqual(perRun.value as? String, "0.25")
        perRun.tap()
        perRun.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "0.01")
        app.buttons["modelLabKeyboardDone"].tap()
        XCTAssertEqual(perRun.value as? String, "0.01")
        app.buttons["modelLabExperiment-planDraft"].tap()
        app.buttons["modelLabRun"].tap()
        allowClaude(app)
        let card = element(app, "modelLabResult-1")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("Blocked by your spend limit: this run could cost up to $0."), card.label)
        XCTAssertTrue(card.label.contains("your per-run limit is $0.01."), card.label)
        XCTAssertEqual(element(app, "costTotal").value as? String, "$0.00")
        keepScreenshot(of: app, named: "Claude - blocked by the per-run cap")
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
        XCTAssertTrue(element(app, "costTotal").waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func allowClaude(_ app: XCUIApplication) {
        let allow = app.buttons["consentAllow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Send summaries to Anthropic?"].exists)
        allow.tap()
        XCTAssertTrue(allow.waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func saveKey(_ app: XCUIApplication, _ key: String) {
        let field = app.secureTextFields["anthropicKeyField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(key)
        app.buttons["anthropicKeySave"].tap()
        XCTAssertTrue(element(app, "anthropicKeyStatus").waitForLabel("Saved · ends \u{2026}\(key.suffix(4))", timeout: 5))
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
    func waitForLabel(_ label: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: self)], timeout: timeout) == .completed
    }

    func waitForValue(_ value: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: self)], timeout: timeout) == .completed
    }
}
