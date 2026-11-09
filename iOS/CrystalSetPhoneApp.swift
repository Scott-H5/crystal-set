// CrystalSetPhoneApp.swift
//
// Where the iPhone version starts. Like the Mac's CrystalSetApp.swift, it
// creates the one AppModel (Shared/Models.swift) and shows the main screen,
// RootView (PhoneViews.swift). The iPhone has no menu bar, so there are no
// menus here; everything is on screen or in VoiceOver's Actions rotor.

import SwiftUI

// `@main` marks where the program begins.
@main
struct CrystalSetPhoneApp: App {
    // Created once and kept for as long as the app runs.
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                // Makes the model available to every screen.
                .environmentObject(model)
        }
    }
}
