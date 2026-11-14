// ScreenshotTests.swift (iPhone)
//
// Takes a screenshot of each screen in Light and Dark Mode, for checking how
// the app looks (a visual review, or App Store screenshots later). Nothing
// is judged here; the pictures are saved with the test results.
//
// Run it with:
//   ~/dev/crystal-set/screenshots.sh ios
// which copies the pictures to build/screenshots-ios.
//
// Like the accessibility audit, it works with VoiceOver on: it touches an
// item, then double-taps it, as a VoiceOver user would.

import XCTest

final class ScreenshotTests: XCTestCase {
    func testScreensInLightAndDarkMode() throws {
        for (mode, name) in [(XCUIDevice.Appearance.light, "Light"), (.dark, "Dark")] {
            // Switches the whole device's appearance for the test.
            XCUIDevice.shared.appearance = mode
            let app = XCUIApplication()
            app.launch()
            sleep(2)
            shoot("\(name) 1 Favorites")

            // Play the first favorite, so the Now Playing bar and screen
            // have something to show.
            // (With pinned stations, the first row is the Pinned section, so
            // take the first row of the list itself.)
            _ = app.cells.firstMatch.waitForExistence(timeout: 5)
            let first = app.staticTexts["Pinned"].exists ? app.cells.element(boundBy: 1) : app.cells.firstMatch
            if first.exists { activate(first) }
            sleep(4)
            shoot("\(name) 2 Favorites, playing")

            activate(app.tabBars.buttons["Search"])
            shoot("\(name) 3 Search")

            activate(app.tabBars.buttons["Now Playing"])
            sleep(1)
            shoot("\(name) 4 Now Playing")

            let stop = app.buttons["Stop"]
            if stop.exists && stop.isEnabled { activate(stop) }
            app.terminate()
        }
        // Leave the device in Light Mode.
        XCUIDevice.shared.appearance = .light
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // Touch, then double-tap if VoiceOver is running (see AccessibilityAuditTests).
    private func activate(_ element: XCUIElement) {
        element.tap()
        if UIAccessibility.isVoiceOverRunning { element.doubleTap() }
        sleep(1)
    }
}
