import SwiftUI

@main
struct CrystalSetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Crystal Set", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .commands {
            StationCommands(model: model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - Menu commands

struct StationCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Station…") { model.showingAddSheet = true }
                .keyboardShortcut("n")
            Button("Import Favorites…") { model.showingImporter = true }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }
        // No printing in this app; frees Command-P for Pause.
        CommandGroup(replacing: .printItem) {}

        // Playback. Space in a station table also plays or pauses.
        CommandMenu("Controls") {
            Button("Play Selected Station") { model.playSelected() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.selectedStation == nil)
            Button("Pause or Resume") { model.player.togglePause() }
                .keyboardShortcut("p")
            Button("Stop") { model.player.stop() }
                .keyboardShortcut(".")
                .disabled(model.showingAddSheet)  // Command-Period cancels the sheet
            Button("Reconnect") { model.player.reconnect() }
                .keyboardShortcut("r")

            Divider()

            Button("Next Station") { model.playAdjacent(1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(arrowKeysBelongToText)
            Button("Previous Station") { model.playAdjacent(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(arrowKeysBelongToText)

            Divider()

            Button("Volume Up") { model.changeVolume(by: 0.05) }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(arrowKeysBelongToText)
            Button("Volume Down") { model.changeVolume(by: -0.05) }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(arrowKeysBelongToText)

            Divider()

            Button("What's Playing") { model.player.announceStatus() }
                .keyboardShortcut("i")
            Button("Show Current Station") { model.showCurrentStation() }
                .keyboardShortcut("l")
        }

        CommandMenu("Station") {
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

    /// While typing in a text field, Command-arrow keys move the text cursor,
    /// so those menu items step aside (a disabled item passes the key through).
    private var arrowKeysBelongToText: Bool {
        model.isEditingText || model.showingAddSheet
    }

    private var favoriteToggleTitle: String {
        if let station = model.selectedStation, model.isFavorite(station) {
            return "Remove from Favorites"
        }
        return "Add to Favorites"
    }
}
