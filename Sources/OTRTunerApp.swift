import SwiftUI

@main
struct OTRTunerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("OTR Tuner", id: "main") {
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

        CommandMenu("Station") {
            Button("Play Selected Station") { model.playSelected() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.selectedStation == nil)
            Button("Pause or Resume") { model.player.togglePause() }
                .keyboardShortcut("p")
            Button("Stop") { model.player.stop() }
                .keyboardShortcut(".")
            Button("What's Playing") { model.player.announceStatus() }
                .keyboardShortcut("i")

            Divider()

            Button(favoriteToggleTitle) { model.toggleFavoriteForSelection() }
                .keyboardShortcut("d")
                .disabled(model.selectedStation == nil)
            Button("Move Favorite Up") { model.moveSelectedFavorite(by: -1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(model.tab != .favorites || model.favoriteSelection == nil)
            Button("Move Favorite Down") { model.moveSelectedFavorite(by: 1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(model.tab != .favorites || model.favoriteSelection == nil)

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

    private var favoriteToggleTitle: String {
        if let station = model.selectedStation, model.isFavorite(station) {
            return "Remove from Favorites"
        }
        return "Add to Favorites"
    }
}
