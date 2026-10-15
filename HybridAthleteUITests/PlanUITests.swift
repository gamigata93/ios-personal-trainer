import XCTest

/// Race setup, building the plan, and landing on Home. Launch arguments are
/// the DEBUG options in CompositionRoot.DebugOptions.
final class PlanUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCustomRaceBuildsAPlanAndShowsItsSessions() throws {
        let app = launchToStartingPoint()
        app.buttons["startingPoint.customRace"].tap()

        // Blank setup: nothing chosen.
        let raceDay = app.buttons["raceSetup.raceDay"]
        XCTAssertTrue(raceDay.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["raceSetup.dayCount"].label, "Choose at least 2")

        raceDay.tap()
        let done = app.buttons["raceSetup.datePickerDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap() // accepts the picker's starting day, 12 weeks out

        for day in ["tuesday", "thursday", "sunday"] {
            app.buttons["raceSetup.day.\(day)"].tap()
        }
        XCTAssertEqual(app.staticTexts["raceSetup.dayCount"].label, "3 days a week")

        let distance = app.textFields["raceSetup.distance"]
        distance.tap()
        distance.typeText("10")
        app.buttons["raceSetup.keyboardDone"].tap()
        keepScreenshot(of: app, named: "Race setup - custom")

        app.buttons["raceSetup.build"].tap()

        XCTAssertTrue(element(app, "home.countdown").waitForExistence(timeout: 10))
        let days = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.day.'"))
        XCTAssertEqual(days.count, 7)
        keepScreenshot(of: app, named: "Home after building")
    }

    @MainActor
    func testSuggestedPlanIsPrefilledButNeedsTrainingDays() throws {
        let app = launchToStartingPoint()
        app.buttons["startingPoint.continue"].tap()

        XCTAssertTrue(element(app, "raceSetup.prefilled").waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["raceSetup.distance"].value as? String, "5")
        XCTAssertNotEqual(app.buttons["raceSetup.raceDay"].value as? String, "Choose a date")
        keepScreenshot(of: app, named: "Race setup - suggested")

        // Looks disabled; a tap only explains what is missing.
        app.buttons["raceSetup.build"].tap()
        XCTAssertEqual(app.staticTexts["raceSetup.problem"].label, "Choose at least 2 training days.")
        XCTAssertFalse(element(app, "generating.title").exists)
        XCTAssertFalse(element(app, "home.countdown").exists)
    }

    // MARK: Helpers

    @MainActor
    private func launchToStartingPoint() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-useInMemoryStores", "-resetCache", "-authorized"]
        app.launch()
        XCTAssertTrue(app.buttons["plan.fiveK"].waitForExistence(timeout: 10))
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
