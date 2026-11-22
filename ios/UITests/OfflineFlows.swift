import XCTest

/// Runs the real application and Rust core. No alternate production code path or fake answers.
@MainActor
final class OfflineFlows: XCTestCase {
    private func openApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        if app.staticTexts["What offline means on iOS"].waitForExistence(timeout: 5) {
            let button = app.buttons["Open my library"]
            for _ in 0..<5 where !button.isHittable { app.swipeUp() }
            XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        }
        XCTAssertTrue(app.tabBars.buttons["Ask"].waitForExistence(timeout: 30))
        return app
    }

    func testOfflineQuestionSurvivesRelaunch() {
        let app = openApp()
        app.tabBars.buttons["Ask"].tap()
        let input = app.textFields["ask-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap(); input.typeText("What is the copper sparrow verification marker?")
        app.buttons["ask-send"].tap()
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 60))
        app.tabBars.buttons["History"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "copper sparrow")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        app.tabBars.buttons["History"].tap()
        let restored = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "copper sparrow")).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 15)); restored.tap()
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Offline answer restored from local history"; attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLibraryAndSettingsAreNative() {
        let app = openApp()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons["Add to your library"].waitForExistence(timeout: 15))
        app.buttons["Add to your library"].tap()
        XCTAssertTrue(app.buttons["Add a document"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap() // Outside the native menu.
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Native offline settings"; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
