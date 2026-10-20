import XCTest

/// Race setup's distance range (5 km to a full marathon), chips and comma input.
final class RaceScopeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRangeChipsAndCommaInput() throws {
        let app = XCUIApplication()
        // A dot locale: chips fill "21.1"; typing a comma must still work.
        app.launchArguments = ["-useInMemoryStores", "-resetCache", "-authorized", "-planDelay", "0", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["plan.fiveK"].waitForExistence(timeout: 10))
        app.buttons["startingPoint.customRace"].tap()

        let field = app.textFields["raceDistanceField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "raceDistanceHelp").label, "From 5 km up to a full marathon (42.195 km).")
        XCTAssertTrue(element(app, "raceSetup.medicalNote").label.hasPrefix("General training guidance, not medical advice."))
        for chip in ["5K", "10K", "Half", "Marathon"] {
            XCTAssertFalse(app.buttons["distanceChip-\(chip)"].isSelected, chip)
        }

        // A valid date and days, so only the distance decides.
        app.buttons["raceSetup.raceDay"].tap()
        app.buttons["raceSetup.datePickerDone"].tap()
        for day in ["tuesday", "thursday", "sunday"] {
            app.buttons["raceSetup.day.\(day)"].tap()
        }

        // 4 km: the range message, and Build does not go on.
        type(app, field, "4")
        let error = element(app, "raceDistanceError")
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "Pick a race distance from 5 km up to a full marathon (42.195 km).")
        app.buttons["raceSetup.build"].tap()
        XCTAssertFalse(element(app, "generating.title").exists)
        keepScreenshot(of: app, named: "Race setup - out of range")

        // 42,2 with a comma is accepted and selects Marathon.
        type(app, field, "42,2")
        XCTAssertTrue(error.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["distanceChip-Marathon"].isSelected)

        // The Half chip fills 21.1.
        app.buttons["distanceChip-Half"].tap()
        XCTAssertEqual(field.value as? String, "21.1")
        XCTAssertTrue(app.buttons["distanceChip-Half"].isSelected)
        XCTAssertEqual(app.buttons["distanceChip-Half"].label, "Set distance to 21.1 kilometres, half marathon")
        keepScreenshot(of: app, named: "Race setup - Half chip")

        // 50 km: the range message again.
        type(app, field, "50")
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["distanceChip-Marathon"].isSelected)
    }

    // MARK: Helpers

    /// Replaces the field's text and leaves the field (so the error rule applies).
    @MainActor
    private func type(_ app: XCUIApplication, _ field: XCUIElement, _ text: String) {
        field.tap()
        let current = field.value as? String ?? ""
        if !current.isEmpty, current != "10" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
        app.buttons["raceSetup.keyboardDone"].tap()
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
