// CrystalSetApp.swift
//
// Where the app starts. It:
//   - creates the one AppModel (Models.swift) that the whole app shares,
//   - opens the main window, which shows ContentView (ContentView.swift),
//   - builds the menu bar: the File, Controls and Station menus and their
//     keyboard shortcuts.
//
// To add a keyboard shortcut, add a Button to one of the menus below and give
// it a .keyboardShortcut. See docs/HOW-IT-WORKS.md for a worked example.

// SwiftUI is Apple's toolkit for describing windows, buttons and menus.
import SwiftUI

// `@main` marks where the program begins. An `App` describes the app's windows and menus.
@main
struct CrystalSetApp: App {
    // Connects the old-style AppKit "app delegate" below, for one Mac setting
    // SwiftUI doesn't offer directly.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // `@StateObject` creates the AppModel once and keeps it for as long as the app runs.
    @StateObject private var model = AppModel()

    // `body` describes what the app is made of.
    var body: some Scene {
        // A single main window titled "Crystal Set". (`Window` allows only one,
        // unlike `WindowGroup`, which allows File > New Window.)
        Window("Crystal Set", id: "main") {
            ContentView()
                // Makes the model available to every view inside the window.
                .environmentObject(model)
        }
        .commands {
            // The menus, defined below.
            StationCommands(model: model, player: model.player)
        }
    }
}

/// Handles one Mac behavior: quitting the app when its window closes.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - Menu commands

/// The app's menus and keyboard shortcuts.
///
/// Each `Button` is a menu item: its text, then in braces the code to run when
/// it's chosen. `.keyboardShortcut("p")` means Command-P; `modifiers:` adds
/// keys such as Shift or Option. `.disabled(...)` dims the item when the
/// condition is true. A dimmed item's shortcut key passes through to whatever
/// has focus, such as a text field.
struct StationCommands: Commands {
    // `@ObservedObject` means "redraw the menus when this changes", so item
    // titles and dimming stay up to date.
    @ObservedObject var model: AppModel
    @ObservedObject var player: Player

    var body: some Commands {
        // The File menu. `replacing: .newItem` swaps out the standard
        // "New Window" item for these.
        CommandGroup(replacing: .newItem) {
            Button("Add Station…") { model.showingAddSheet = true }
                .keyboardShortcut("n")
            Button("Import Favorites…") { model.showingImporter = true }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Export Favorites…") { model.showingExporter = true }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.favorites.isEmpty)
        }
        // No printing in this app; frees Command-P for Pause.
        CommandGroup(replacing: .printItem) {}

        // The Controls menu: playback. Space in a station table also plays or pauses.
        CommandMenu("Controls") {
            Button("Play Selected Station") { model.playSelected() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.selectedStation == nil)
            Button("Pause or Resume") { model.player.togglePause() }
                .keyboardShortcut("p")
            // Dimmed while the Add Station sheet is open, because Command-Period
            // means Cancel there.
            Button("Stop") { model.player.stop() }
                .keyboardShortcut(".")
                .disabled(model.showingAddSheet)
            Button("Reconnect") { model.player.reconnect() }
                .keyboardShortcut("r")

            // A separator line in the menu.
            Divider()

            Button("Next Station") { model.playAdjacent(1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(arrowKeysBelongToText)
            Button("Previous Station") { model.playAdjacent(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(arrowKeysBelongToText)

            Divider()

            // 0.05 is a 5% step. Change both numbers to change the step.
            Button("Volume Up") { model.changeVolume(by: 0.05) }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(arrowKeysBelongToText)
            Button("Volume Down") { model.changeVolume(by: -0.05) }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(arrowKeysBelongToText)

            Divider()

            // A Picker in a menu becomes a submenu, with a checkmark on the current choice.
            // `.tag(...)` is the value each choice stands for; 0 means Off.
            Picker("Sleep Timer", selection: sleepTimerBinding) {
                Text("Off").tag(0)
                ForEach(Player.sleepTimerChoices, id: \.self) { minutes in
                    Text("\(minutes) Minutes").tag(minutes)
                }
            }
            Button("Change Sleep Timer") { player.cycleSleepTimer() }
                .keyboardShortcut("t")

            Divider()

            Button("What's Playing") { model.player.announceStatus() }
                .keyboardShortcut("i")
            Button("Show Current Station") { model.showCurrentStation() }
                .keyboardShortcut("l")
        }

        // The Station menu: favorites and moving around the window.
        CommandMenu("Station") {
            // The title changes between "Add to Favorites" and "Remove from Favorites".
            Button(favoriteToggleTitle) { model.toggleFavoriteForSelection() }
                .keyboardShortcut("d")
                .disabled(model.selectedStation == nil)
            Button("Move Favorite Up") { model.moveSelectedFavorite(by: -1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(arrowKeysBelongToText || model.tab != .favorites || model.favoriteSelection == nil)
            Button("Move Favorite Down") { model.moveSelectedFavorite(by: 1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(arrowKeysBelongToText || model.tab != .favorites || model.favoriteSelection == nil)

            Divider()

            Button("Show Favorites") { model.tab = .favorites }
                .keyboardShortcut("1")
            Button("Show Search") { model.tab = .search }
                .keyboardShortcut("2")
            Button("Find Stations…") {
                model.tab = .search
                model.focusSearchField = true
            }
            .keyboardShortcut("f")
        }
    }

    // A "binding" connects a control to a value in both directions: the
    // Sleep Timer submenu shows the player's current setting (get), and
    // choosing an item starts that timer (set).
    private var sleepTimerBinding: Binding<Int> {
        Binding(get: { player.sleepTimerMinutes },
                set: { player.setSleepTimer(minutes: $0) })
    }

    /// While typing in a text field, Command-arrow keys move the text cursor,
    /// so those menu items step aside (a disabled item passes the key through).
    private var arrowKeysBelongToText: Bool {
        model.isEditingText || model.showingAddSheet
    }

    // The Command-D menu item's title, depending on the selected station.
    private var favoriteToggleTitle: String {
        if let station = model.selectedStation, model.isFavorite(station) {
            return "Remove from Favorites"
        }
        return "Add to Favorites"
    }
}
