// AccessibilityAuditTests.swift (iPhone)
//
// Runs Apple's automatic accessibility audit on each of Crystal Set's
// screens. The audit is the same one Xcode's Accessibility Inspector runs:
// it looks for elements VoiceOver can't name, text that is cut off or
// doesn't grow with Larger Text, low color contrast, touch targets that are
// too small, and similar problems.
//
// How to run it (with the iPhone connected and unlocked):
//   bash ~/dev/crystal-set/audit.sh ios
//
// Each problem found is printed as "AUDIT: ..." with the element it's on.
// The test doesn't stop at the first problem; it lists them all, then fails
// if there were any, so the list can be worked through.
//
// XCUITest ("UI testing") drives the real app the way a person would, by
// finding buttons by their labels and tapping them. So a test that can find
// "Search" by name is also a small check that VoiceOver can.

import XCTest

final class AccessibilityAuditTests: XCTestCase {
    private var issues: [String] = []
    // Findings on elements that aren't visible (see audit(_:screen:)).
    private var offScreen = 0

    override func setUp() {
        continueAfterFailure = true
    }

    /// Audits each tab at the normal text size.
    func testAuditAtDefaultTextSize() throws {
        try auditAllScreens(textSize: nil)
    }

    /// Audits each tab at the largest Accessibility text size, the setting
    /// most likely to cut text off or push controls off the screen.
    func testAuditAtLargestTextSize() throws {
        try auditAllScreens(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    private func auditAllScreens(textSize: String?) throws {
        let app = XCUIApplication()
        if let textSize {
            // Launch the app as if Settings > Accessibility > Display & Text
            // Size > Larger Text were set to this size. Only this app is
            // affected, and only for this test run.
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        app.launch()
        let size = textSize == nil ? "default text" : "largest text"

        try audit(app, screen: "Favorites (\(size))")

        // Play the first favorite, so the Now Playing bar appears, and audit again.
        let firstStation = app.cells.firstMatch
        if firstStation.waitForExistence(timeout: 5) {
            activate(firstStation)
            sleep(3)
            try audit(app, screen: "Favorites, playing (\(size))")
        }

        activate(app.tabBars.buttons["Search"])
        try audit(app, screen: "Search (\(size))")

        activate(app.tabBars.buttons["Now Playing"])
        try audit(app, screen: "Now Playing (\(size))")

        // Stop what the test started.
        let stop = app.buttons["Stop"]
        if stop.exists && stop.isEnabled { activate(stop) }

        report()
    }

    /// Taps an element the way a person would with VoiceOver on or off.
    ///
    /// With VoiceOver running (as on the developer's own iPhone), a single tap
    /// only moves the VoiceOver cursor to the element; it takes a double tap
    /// to activate it. Without this, the test's taps did nothing, and every
    /// screen it "audited" was really the Favorites tab.
    private func activate(_ element: XCUIElement) {
        element.tap()
        if UIAccessibility.isVoiceOverRunning {
            element.doubleTap()
        }
        sleep(1)
    }

    private func audit(_ app: XCUIApplication, screen: String) throws {
        // A screenshot of what the audit looked at, saved in the test results
        // (audit.sh copies them to build/audit-screenshots), so a finding can
        // be checked against what's actually on screen.
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = screen
        shot.lifetime = .keepAlways
        add(shot)
        try app.performAccessibilityAudit { issue in
            // The audit also measures rows that aren't on screen (further down
            // the list, behind the Now Playing bar, or on another tab, which
            // SwiftUI keeps loaded). Their contrast is measured against
            // whatever happens to be drawn there, so those results are
            // meaningless. They're counted, not listed.
            if let element = issue.element, element.exists, !element.isHittable {
                self.offScreen += 1
                return true
            }
            let element = issue.element.map {
                "\($0.elementType) \"\($0.label)\" at \(Int($0.frame.minX)),\(Int($0.frame.minY)) size \(Int($0.frame.width))x\(Int($0.frame.height))"
            } ?? "(no element)"
            let line = "AUDIT: [\(screen)] \(issue.auditType): \(issue.compactDescription). Element: \(element). \(issue.detailedDescription)"
            print(line)
            self.issues.append(line)
            // true = "handled": keep going instead of failing straight away.
            return true
        }
    }

    private func report() {
        print("AUDIT SUMMARY: \(issues.count) issue(s) on screen; \(offScreen) set aside because the element wasn't visible")
        if !issues.isEmpty {
            XCTFail("\(issues.count) accessibility issue(s):\n" + issues.joined(separator: "\n"))
        }
        issues.removeAll()
        offScreen = 0
    }
}
