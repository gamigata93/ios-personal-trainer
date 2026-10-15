import XCTest

/// Launch arguments are the DEBUG options in CompositionRoot.DebugOptions.
final class OnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFreshInstallConnectsHealthThenFillsInSectionBySection() throws {
        let app = launch(["-useInMemoryStores", "-resetCache", "-simulate", "slow"])

        let allow = app.buttons["connect.allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10))
        keepScreenshot(of: app, named: "Connect Health")
        allow.tap()

        // Nothing is cached yet, so the dashboard starts as placeholders.
        XCTAssertTrue(element(app, "skeleton.vo2Max").waitForExistence(timeout: 5))
        let primary = app.buttons["startingPoint.continue"]
        XCTAssertFalse(primary.isEnabled)
        XCTAssertTrue(app.buttons["startingPoint.customRace"].isEnabled)
        keepScreenshot(of: app, named: "Starting point - loading")

        // Sections land one by one; workouts (and the plans) come last.
        XCTAssertTrue(element(app, "startingPoint.vo2Max").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["plan.fiveK"].waitForExistence(timeout: 10))
        XCTAssertTrue(primary.isEnabled)
        keepScreenshot(of: app, named: "Starting point - loaded")

        primary.tap()
        XCTAssertTrue(app.buttons["raceSetup.build"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSecondLaunchShowsTheCacheBeforeTheReadFinishes() throws {
        // First launch: read everything once so the cache is saved.
        let first = launch(["-useInMemoryStores", "-resetCache", "-authorized"])
        XCTAssertTrue(first.buttons["plan.fiveK"].waitForExistence(timeout: 10))
        first.terminate()

        // Second launch: the live workouts read takes 4 s, so plans this early come from the cache.
        let second = launch(["-useInMemoryStores", "-authorized", "-simulate", "slow"])
        XCTAssertTrue(second.buttons["plan.fiveK"].waitForExistence(timeout: 2.5))
        XCTAssertFalse(element(second, "skeleton.vo2Max").exists)
        keepScreenshot(of: second, named: "Starting point - from cache")
    }

    @MainActor
    func testLockedShowsTheBannerAndCachedValues() throws {
        let app = launch(["-useInMemoryStores", "-resetCache", "-authorized", "-simulate", "locked"])

        XCTAssertTrue(element(app, "startingPoint.lockedBanner").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "startingPoint.vo2Max").exists)
        XCTAssertTrue(app.buttons["plan.fiveK"].waitForExistence(timeout: 5))
        keepScreenshot(of: app, named: "Starting point - locked")
    }

    // MARK: Helpers

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
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
