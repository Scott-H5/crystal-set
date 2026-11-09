// ContentView.swift
//
// What you see in the main window, built with SwiftUI:
//   - ContentView: the whole window. Favorites and Search tabs on top, the
//     Now Playing bar along the bottom, plus the Add Station sheet, the
//     Import and Export file panels, and the result alert.
//   - FavoritesView: the Favorites tab.
//   - SearchView: the Search tab.
//   - NowPlayingBar: station name, status, Pause/Resume, Stop, sleep timer, volume.
//   - AddStationSheet: the form for adding a station by its address.
//
// How SwiftUI works, in short: each `View` has a `body` that *describes* what
// to show, built from standard controls (Text, Button, TextField, Picker,
// Slider). When a value it reads from the AppModel or Player changes, SwiftUI
// works out the body again and updates the window. Views don't make
// decisions; their buttons call functions on the AppModel or Player.
//
// The station tables themselves are in StationTable.swift.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main window

struct ContentView: View {
    // `@EnvironmentObject` picks up the shared AppModel handed down by CrystalSetApp.swift.
    @EnvironmentObject private var model: AppModel

    var body: some View {
        // A VStack stacks things top to bottom. `spacing: 0` leaves no gap.
        VStack(spacing: 0) {
            // The two tabs. `$model.tab` is a binding: picking a tab changes
            // model.tab, and changing model.tab (Command-1, Command-2) picks the tab.
            TabView(selection: $model.tab) {
                FavoritesView()
                    .tabItem { Text("Favorites") }
                    .tag(AppModel.Tab.favorites)
                SearchView()
                    .tabItem { Text("Search") }
                    .tag(AppModel.Tab.search)
            }
            .padding([.horizontal, .top])
            // The Save panel for File > Export Favorites. It appears when
            // model.showingExporter becomes true.
            // Kept on a different view from the importer: SwiftUI can mix up
            // two file panels attached to the same view.
            .fileExporter(isPresented: $model.showingExporter,
                          document: model.favoritesDocument,
                          contentType: .json,
                          defaultFilename: "Crystal Set Favorites") { result in
                model.exportFinished(result)
            }

            // A thin line between the tabs and the Now Playing bar.
            Divider().padding(.top)

            NowPlayingBar(player: model.player)
        }
        // The smallest the window can be, in points.
        .frame(minWidth: 780, minHeight: 460)
        // The Add Station sheet slides down when model.showingAddSheet becomes true.
        .sheet(isPresented: $model.showingAddSheet) {
            AddStationSheet()
                .environmentObject(model)
        }
        // The Open panel for File > Import Favorites, limited to JSON files.
        .fileImporter(isPresented: $model.showingImporter, allowedContentTypes: [.json]) { result in
            model.importFavorites(from: result)
        }
        // The alert reporting an import or export, such as "Imported 3 stations."
        .alert(model.resultTitle, isPresented: $model.showingImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.importMessage)
        }
    }
}

// MARK: - Favorites

/// The Favorites tab: the favorites table and the buttons below it.
struct FavoritesView: View {
    @EnvironmentObject private var model: AppModel

    // The selected favorite, or nil. Buttons use it to know what to act on.
    private var selected: Station? {
        model.favorites.first { $0.id == model.favoriteSelection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // With no favorites, show a hint instead of an empty table.
            if model.favorites.isEmpty {
                // Spacers push the text to the middle.
                Spacer()
                Text("No favorites yet. Search for stations, add one by its stream address, or import a JSON favorites file.")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                // `allowsDelete: true` turns on Command-Delete for this table only.
                StationTable(stations: model.favorites,
                             selection: $model.favoriteSelection,
                             title: "Favorites",
                             allowsDelete: true)
            }

            // An HStack lines things up left to right: the row of buttons.
            HStack {
                // Each button runs its code only if a station is selected,
                // and is dimmed (.disabled) when there's nothing to act on.
                Button("Play") { if let selected { model.play(selected) } }
                    .disabled(selected == nil)
                Button("Remove") { if let selected { model.removeFromFavorites(selected) } }
                    .disabled(selected == nil)
                // Dimmed for the first favorite, which can't move up.
                Button("Move Up") { model.moveSelectedFavorite(by: -1) }
                    .disabled(selected == nil || model.favorites.first?.id == selected?.id)
                // Dimmed for the last favorite, which can't move down.
                Button("Move Down") { model.moveSelectedFavorite(by: 1) }
                    .disabled(selected == nil || model.favorites.last?.id == selected?.id)
                // Pushes the next buttons to the right-hand side.
                Spacer()
                Button("Add Station…") { model.showingAddSheet = true }
                Button("Import…") { model.showingImporter = true }
                Button("Export…") { model.showingExporter = true }
                    .disabled(model.favorites.isEmpty)
            }
        }
        .padding()
    }
}

// MARK: - Search

/// The Search tab: search field, results table, and buttons.
struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    // Tracks whether the search field has keyboard focus, and can move focus there.
    @FocusState private var searchFieldFocused: Bool

    private var selected: Station? {
        model.results.first { $0.id == model.searchSelection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // "Search for" is the field's label, which VoiceOver reads.
                // `.onSubmit` runs when you press Return in the field.
                TextField("Search for", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFieldFocused)
                    .onSubmit { model.search() }
                // A pop-up button with one choice per SearchField (Tag, Name).
                Picker("Search by", selection: $model.field) {
                    ForEach(SearchField.allCases) { field in
                        Text(field.rawValue).tag(field)
                    }
                }
                // Keep the pop-up button at its natural width.
                .fixedSize()
                Button("Search") { model.search() }
                    .disabled(model.isSearching
                              || model.query.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Status text such as "114 stations found."
            if !model.searchMessage.isEmpty {
                Text(model.searchMessage)
                    .foregroundStyle(.secondary)
            }

            StationTable(stations: model.results,
                         selection: $model.searchSelection,
                         title: "Search results")

            HStack {
                Button("Play") { if let selected { model.play(selected) } }
                    .disabled(selected == nil)
                // Dimmed when the station is already a favorite.
                Button("Add to Favorites") { if let selected { model.addToFavorites(selected) } }
                    .disabled(selected == nil || selected.map(model.isFavorite) == true)
                Spacer()
                // Credit to the free directory the stations come from.
                Text("Station directory from radio-browser.info")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        // Command-F sets model.focusSearchField; these move the cursor into
        // the field, whether or not the Search tab was already showing.
        .onAppear { if model.focusSearchField { focusSearch() } }
        .onChange(of: model.focusSearchField) { wanted in
            if wanted { focusSearch() }
        }
        // Tell the model when the field gains or loses focus, so the
        // Command-arrow menu shortcuts step aside while you type.
        .onChange(of: searchFieldFocused) { focused in
            model.isEditingText = focused
        }
        .onDisappear { model.isEditingText = false }
    }

    private func focusSearch() {
        searchFieldFocused = true
        model.focusSearchField = false
    }
}

// MARK: - Now playing

/// The bar along the bottom of the window.
struct NowPlayingBar: View {
    // Watches the Player directly, so the bar updates as playback changes.
    @ObservedObject var player: Player

    // For example: "Playing — The Shadow — Sleep timer: 20 minutes left".
    private var statusLine: String {
        var parts = [player.state.description]
        if !player.streamTitle.isEmpty { parts.append(player.streamTitle) }
        if let sleep = player.sleepTimerDescription { parts.append(sleep) }
        return parts.joined(separator: " — ")
    }

    var body: some View {
        HStack(spacing: 12) {
            // Station name, with the status line underneath.
            VStack(alignment: .leading, spacing: 2) {
                Text(player.station?.name ?? "Nothing playing")
                    .font(.headline)
                if player.station != nil {
                    Text(statusLine)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            // VoiceOver reads the name and status as one item, beginning "Now playing:".
            .accessibilityElement(children: .combine)
            .accessibilityLabel(player.station.map { "Now playing: \($0.name). \(statusLine)" }
                                ?? "Nothing playing")

            Spacer()

            // The button's title switches between "Pause" and "Resume".
            Button(player.state == .playing || player.state == .connecting ? "Pause" : "Resume") {
                player.togglePause()
            }
            .disabled(player.station == nil)

            Button("Stop") { player.stop() }
                .disabled(!player.isActive)

            // A pop-up button: Off, 15 minutes, 30 minutes, and so on.
            // The binding reads the current setting and starts the chosen timer.
            Picker("Sleep timer", selection: Binding(
                get: { player.sleepTimerMinutes },
                set: { player.setSleepTimer(minutes: $0) }
            )) {
                Text("Off").tag(0)
                ForEach(Player.sleepTimerChoices, id: \.self) { minutes in
                    Text("\(minutes) minutes").tag(minutes)
                }
            }
            .fixedSize()

            // The volume slider, from 0 to 1 in steps of 0.05 (5%).
            Slider(value: $player.volume, in: 0...1, step: 0.05) {
                Text("Volume")
            }
            .frame(width: 170)
            // VoiceOver reads the value as a percentage, such as "80 percent".
            .accessibilityValue("\(Int((player.volume * 100).rounded())) percent")
        }
        .padding()
    }
}

// MARK: - Add station sheet

/// The form for adding a station by its stream address (Command-N).
struct AddStationSheet: View {
    @EnvironmentObject private var model: AppModel
    // Closes the sheet when called.
    @Environment(\.dismiss) private var dismiss
    // `@State` is a value this view keeps for itself: what's typed in each field.
    @State private var name = ""
    @State private var url = ""

    // True when both fields are filled in and the address starts with http or
    // https. The Add button is dimmed until then.
    private var isValid: Bool {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let parsed = URL(string: trimmedURL),
              let scheme = parsed.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && parsed.host != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Marked as a heading, so VoiceOver's heading navigation finds it.
            Text("Add Station")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)

            // A Form lines up labeled fields neatly.
            Form {
                TextField("Name", text: $name)
                TextField("Stream URL", text: $url)
            }

            Text("The stream address starts with http:// or https://. Playlist links ending in .pls or .m3u also work.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                // `.cancelAction` makes Escape and Command-Period press Cancel.
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                // `.defaultAction` makes Return press Add.
                Button("Add") {
                    model.addManual(name: name, url: url)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
