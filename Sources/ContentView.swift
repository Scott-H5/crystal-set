import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main window

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $model.tab) {
                FavoritesView()
                    .tabItem { Text("Favorites") }
                    .tag(AppModel.Tab.favorites)
                SearchView()
                    .tabItem { Text("Search") }
                    .tag(AppModel.Tab.search)
            }
            .padding([.horizontal, .top])
            // Kept on a different view from the importer: SwiftUI can mix up
            // two file panels attached to the same view.
            .fileExporter(isPresented: $model.showingExporter,
                          document: model.favoritesDocument,
                          contentType: .json,
                          defaultFilename: "Crystal Set Favorites") { result in
                model.exportFinished(result)
            }

            Divider().padding(.top)

            NowPlayingBar(player: model.player)
        }
        .frame(minWidth: 780, minHeight: 460)
        .sheet(isPresented: $model.showingAddSheet) {
            AddStationSheet()
                .environmentObject(model)
        }
        .fileImporter(isPresented: $model.showingImporter, allowedContentTypes: [.json]) { result in
            model.importFavorites(from: result)
        }
        .alert(model.resultTitle, isPresented: $model.showingImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.importMessage)
        }
    }
}

// MARK: - Favorites

struct FavoritesView: View {
    @EnvironmentObject private var model: AppModel

    private var selected: Station? {
        model.favorites.first { $0.id == model.favoriteSelection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.favorites.isEmpty {
                Spacer()
                Text("No favorites yet. Search for stations, add one by its stream address, or import a JSON favorites file.")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                StationTable(stations: model.favorites,
                             selection: $model.favoriteSelection,
                             title: "Favorites",
                             allowsDelete: true)
            }

            HStack {
                Button("Play") { if let selected { model.play(selected) } }
                    .disabled(selected == nil)
                Button("Remove") { if let selected { model.removeFromFavorites(selected) } }
                    .disabled(selected == nil)
                Button("Move Up") { model.moveSelectedFavorite(by: -1) }
                    .disabled(selected == nil || model.favorites.first?.id == selected?.id)
                Button("Move Down") { model.moveSelectedFavorite(by: 1) }
                    .disabled(selected == nil || model.favorites.last?.id == selected?.id)
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

struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var searchFieldFocused: Bool

    private var selected: Station? {
        model.results.first { $0.id == model.searchSelection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Search for", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFieldFocused)
                    .onSubmit { model.search() }
                Picker("Search by", selection: $model.field) {
                    ForEach(SearchField.allCases) { field in
                        Text(field.rawValue).tag(field)
                    }
                }
                .fixedSize()
                Button("Search") { model.search() }
                    .disabled(model.isSearching
                              || model.query.trimmingCharacters(in: .whitespaces).isEmpty)
            }

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
                Button("Add to Favorites") { if let selected { model.addToFavorites(selected) } }
                    .disabled(selected == nil || selected.map(model.isFavorite) == true)
                Spacer()
                Text("Station directory from radio-browser.info")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear { if model.focusSearchField { focusSearch() } }
        .onChange(of: model.focusSearchField) { wanted in
            if wanted { focusSearch() }
        }
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

struct NowPlayingBar: View {
    @ObservedObject var player: Player

    private var statusLine: String {
        var parts = [player.state.description]
        if !player.streamTitle.isEmpty { parts.append(player.streamTitle) }
        if let sleep = player.sleepTimerDescription { parts.append(sleep) }
        return parts.joined(separator: " — ")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.station?.name ?? "Nothing playing")
                    .font(.headline)
                if player.station != nil {
                    Text(statusLine)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(player.station.map { "Now playing: \($0.name). \(statusLine)" }
                                ?? "Nothing playing")

            Spacer()

            Button(player.state == .playing || player.state == .connecting ? "Pause" : "Resume") {
                player.togglePause()
            }
            .disabled(player.station == nil)

            Button("Stop") { player.stop() }
                .disabled(!player.isActive)

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

            Slider(value: $player.volume, in: 0...1, step: 0.05) {
                Text("Volume")
            }
            .frame(width: 170)
            .accessibilityValue("\(Int((player.volume * 100).rounded())) percent")
        }
        .padding()
    }
}

// MARK: - Add station sheet

struct AddStationSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""

    private var isValid: Bool {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let parsed = URL(string: trimmedURL),
              let scheme = parsed.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && parsed.host != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Station")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)

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
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
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
