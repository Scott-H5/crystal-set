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

            Divider().padding(.top)

            NowPlayingBar(player: model.player)
        }
        .frame(minWidth: 680, minHeight: 460)
        .sheet(isPresented: $model.showingAddSheet) {
            AddStationSheet()
                .environmentObject(model)
        }
        .fileImporter(isPresented: $model.showingImporter, allowedContentTypes: [.json]) { result in
            model.importFavorites(from: result)
        }
        .alert("Import Favorites", isPresented: $model.showingImportResult) {
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
                             title: "Favorites")
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
    }

    private func focusSearch() {
        searchFieldFocused = true
        model.focusSearchField = false
    }
}

// MARK: - Station table

/// A standard table of stations. Return or double-click plays the selected row,
/// and the context menu (VoiceOver: VO-Shift-M) offers the same actions as the buttons.
struct StationTable: View {
    @EnvironmentObject private var model: AppModel
    let stations: [Station]
    @Binding var selection: Station.ID?
    let title: String

    var body: some View {
        Table(stations, selection: $selection) {
            TableColumn("Name", value: \.name)
            TableColumn("Country", value: \.country)
                .width(min: 80, ideal: 140)
            TableColumn("Format", value: \.formatDescription)
                .width(min: 70, ideal: 100)
            TableColumn("Tags", value: \.tags)
        }
        .contextMenu(forSelectionType: Station.ID.self) { ids in
            if let station = station(for: ids) {
                Button("Play") { model.play(station) }
                if model.isFavorite(station) {
                    Button("Remove from Favorites") { model.removeFromFavorites(station) }
                } else {
                    Button("Add to Favorites") { model.addToFavorites(station) }
                }
            }
        } primaryAction: { ids in
            if let station = station(for: ids) { model.play(station) }
        }
        .accessibilityLabel(title)
    }

    private func station(for ids: Set<Station.ID>) -> Station? {
        guard let id = ids.first else { return nil }
        return stations.first { $0.id == id }
    }
}

// MARK: - Now playing

struct NowPlayingBar: View {
    @ObservedObject var player: Player

    private var statusLine: String {
        var parts = [player.state.description]
        if !player.streamTitle.isEmpty { parts.append(player.streamTitle) }
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

            Slider(value: $player.volume, in: 0...1) {
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
