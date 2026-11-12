// AccessibilityAuditTests.swift (Mac)
//
// Runs Apple's automatic accessibility audit on the Mac window: elements
// VoiceOver can't name, low color contrast, controls without an action
// VoiceOver can perform, and similar problems.
//
// How to run it:
//   ~/dev/crystal-set/audit.sh mac
//
// The first time, macOS asks to let the test runner control the computer
// (System Settings > Privacy & Security > Accessibility), because UI tests
// drive the app the way a person would. Turn it off again afterwards.
//
// Keyboard shortcuts are used instead of clicks, so the test works the same
// with VoiceOver on or off.

import XCTest

final class AccessibilityAuditTests: XCTestCase {
    private var issues: [String] = []

    override func setUp() {
        continueAfterFailure = true
    }

    func testAuditMainWindow() throws {
        let app = XCUIApplication()
        app.launch()
        app.activate()
        sleep(2)

        // Command-1: Favorites.
        app.typeKey("1", modifierFlags: .command)
        try audit(app, screen: "Favorites")

        // Command-Return plays the selected favorite, so the Now Playing
        // controls are showing.
        app.typeKey(.return, modifierFlags: .command)
        sleep(4)
        try audit(app, screen: "Favorites, playing")

        // Command-2: Search.
        app.typeKey("2", modifierFlags: .command)
        sleep(1)
        try audit(app, screen: "Search")

        // Command-Period: Stop.
        app.typeKey(".", modifierFlags: .command)

        print("AUDIT SUMMARY: \(issues.count) issue(s)")
        if !issues.isEmpty {
            XCTFail("\(issues.count) accessibility issue(s):\n" + issues.joined(separator: "\n"))
        }
    }

    private func audit(_ app: XCUIApplication, screen: String) throws {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = screen
        shot.lifetime = .keepAlways
        add(shot)
        try app.performAccessibilityAudit { issue in
            let element = issue.element.map {
                "\($0.elementType) \"\($0.label)\" at \(Int($0.frame.minX)),\(Int($0.frame.minY)) size \(Int($0.frame.width))x\(Int($0.frame.height))"
            } ?? "(no element)"
            let line = "AUDIT: [\(screen)] \(issue.auditType): \(issue.compactDescription). Element: \(element). \(issue.detailedDescription)"
            print(line)
            self.issues.append(line)
            return true
        }
    }
}
