// ScreenshotTests.swift (Mac)
//
// Takes a screenshot of the main window's screens in Light and Dark Mode,
// for checking how the app looks. Nothing is judged; the pictures are saved
// with the test results. Like the audit, it needs the test runner (or the
// app running the tests) allowed in System Settings > Privacy & Security >
// Device Control and Data Access, and keyboard shortcuts instead of clicks.

import XCTest

final class ScreenshotTests: XCTestCase {
    func testWindowInLightAndDarkMode() throws {
        for name in ["Light", "Dark"] {
            let app = XCUIApplication()
            // Starts the app in this appearance, whatever the Mac is set to.
            // (The setting is read from these arguments, for this launch only.)
            app.launchArguments += ["-AppleInterfaceStyle", name == "Dark" ? "Dark" : "Light"]
            app.launch()
            app.activate()
            sleep(2)
            app.typeKey("1", modifierFlags: .command)
            sleep(1)
            shoot(app, "\(name) 1 Favorites")
            app.typeKey(.return, modifierFlags: .command)
            sleep(4)
            shoot(app, "\(name) 2 Favorites, playing")
            app.typeKey("2", modifierFlags: .command)
            app.typeKey(.return, modifierFlags: [])
            sleep(5)
            shoot(app, "\(name) 3 Search")
            app.typeKey(".", modifierFlags: .command)
            app.terminate()
        }
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
