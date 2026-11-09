// PhoneViews.swift
//
// The iPhone version's screens, built with SwiftUI:
//   - RootView: the three tabs (Favorites, Search, Now Playing), plus the
//     Import and Export file panels, the result alert, the sleep timer
//     pop-up, and Magic Tap.
//   - SleepTimerPicker: the sleep timer choices, used in two places.
//   - FavoritesScreen, SearchScreen, NowPlayingScreen: one per tab.
//   - StationRow: one station in a list. Double-tap plays it; VoiceOver's
//     Actions rotor (swipe up or down) offers the other actions. In Edit
//     mode, double-tapping a favorite renames it instead, and the rotor
//     switches to Move Up, Move Down and Delete.
//   - MiniPlayer: the Now Playing bar at the bottom of the lists.
//
// There's no Add Station form: the Search field takes a stream address as
// well as a name or tag, and shows it as a result you can play and add.
//
// These screens use the same AppModel and Player as the Mac version, so
// favorites, search, playback and the sleep timer all behave the same.
// Only the screens differ.
//
// VoiceOver on iPhone, in brief:
//   - Double-tap activates the selected item (here: plays a station).
//   - The Actions rotor lists extra actions for an item; swipe up or down
//     to choose one, then double-tap. `.accessibilityAction(named:)` and
//     `.accessibilityActions { }` add items to it.
//   - Magic Tap (a two-finger double-tap anywhere) pauses and resumes,
//     as in Music and Podcasts.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Root

/// The tabs. The Mac's AppModel.Tab has only Favorites and Search; the
/// iPhone adds a Now Playing tab, so it keeps its own list of tabs.
enum PhoneTab: Hashable { case favorites, search, nowPlaying }

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab: PhoneTab = .favorites

    var body: some View {
        TabView(selection: $tab) {
            FavoritesScreen()
                .tabItem { Label("Favorites", systemImage: "star") }
                .tag(PhoneTab.favorites)
            SearchScreen()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(PhoneTab.search)
            NowPlayingScreen(player: model.player)
                .tabItem { Label("Now Playing", systemImage: "radio") }
                .tag(PhoneTab.nowPlaying)
        }
        // Magic Tap: pause or resume from anywhere in the app.
        .accessibilityAction(.magicTap) { model.player.togglePause() }
        // Keep the AppModel's tab in step, so Next and Previous Station use
        // the list you were last looking at.
        .onChange(of: tab) { _, newTab in
            switch newTab {
            case .favorites: model.tab = .favorites
            case .search: model.tab = .search
            case .nowPlaying: break
            }
        }
        // When the AppModel switches tab (after adding or importing a
        // station), follow it.
        .onChange(of: model.tab) { _, newTab in
            tab = newTab == .favorites ? .favorites : .search
        }
        .fileImporter(isPresented: $model.showingImporter, allowedContentTypes: [.json]) { result in
            model.importFavorites(from: result)
        }
        // The sleep timer pop-up, opened by "Sleep Timer…" in the Actions
        // rotor of the Now Playing bar and of the station that's playing.
        // The rotor can't hold a submenu, so this standard pop-up list
        // (an "action sheet") stands in for one. Each choice is a button;
        // the current one says so, since a pop-up can't show a checkmark.
        .confirmationDialog("Sleep Timer", isPresented: $model.showingSleepTimerChoices,
                            titleVisibility: .visible) {
            ForEach([0] + Player.sleepTimerChoices, id: \.self) { minutes in
                let name = minutes == 0 ? "Off" : "\(minutes) minutes"
                Button(minutes == model.player.sleepTimerMinutes ? "\(name) (current)" : name) {
                    model.player.setSleepTimer(minutes: minutes)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.player.sleepTimerDescription ?? "The sound fades out over the last 30 seconds, then playback stops.")
        }
        .alert(model.resultTitle, isPresented: $model.showingImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.importMessage)
        }
    }
}

// MARK: - Favorites

struct FavoritesScreen: View {
    @EnvironmentObject private var model: AppModel
    // What's typed in the Rename alert's text field.
    @State private var newName = ""
    // Whether Edit mode is on. The Edit button turns it on and off; this
    // screen keeps it itself (see `.environment` below) so it can tell.
    @State private var editMode: EditMode = .inactive

    var body: some View {
        // A NavigationStack gives the screen its title bar and toolbar.
        NavigationStack {
            Group {
                if model.favorites.isEmpty {
                    // Apple's standard "nothing here yet" message.
                    ContentUnavailableView(
                        "No Favorites",
                        systemImage: "star",
                        description: Text("Use the Search tab to find stations by name or tag, or paste a stream address there. You can also import a JSON favorites file from the More menu.")
                    )
                } else {
                    List {
                        ForEach(model.favorites) { station in
                            StationRow(station: station, player: model.player, inFavorites: true)
                        }
                        // In Edit mode, drag handles reorder and delete buttons remove.
                        .onMove { from, to in model.favorites.move(fromOffsets: from, toOffset: to) }
                        // The delete buttons are attached only in Edit mode (nil
                        // means none). Otherwise iOS also adds its own swipe-to-
                        // delete, which put a second Delete in VoiceOver's Actions
                        // rotor beside the row's own Remove swipe action.
                        .onDelete(perform: editMode.isEditing ? deleteFavorites : nil)
                    }
                }
            }
            .navigationTitle("Favorites")
            // The Rename alert, with a text field holding the current name.
            // It opens when model.renamingStation is set (see StationRow).
            .alert("Rename Station", isPresented: Binding(
                get: { model.renamingStation != nil },
                set: { if !$0 { model.renamingStation = nil } }
            )) {
                TextField("Name", text: $newName)
                Button("Rename") {
                    if let station = model.renamingStation { model.renameFavorite(station, to: newName) }
                }
                Button("Cancel", role: .cancel) {}
            }
            // Start the text field with the station's current name.
            .onChange(of: model.renamingStation) { _, station in
                if let station { newName = station.name }
            }
            .toolbar {
                // Edit mode, for reordering and deleting.
                ToolbarItem(placement: .topBarLeading) {
                    if !model.favorites.isEmpty { EditButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // First in the menu, since it's the item used most at bedtime.
                        // A submenu with a checkmark on the current choice, so the
                        // timer can be set without going to the Now Playing tab.
                        SleepTimerPicker(player: model.player)

                        Divider()

                        Button("Import Favorites…", systemImage: "square.and.arrow.down") {
                            model.showingImporter = true
                        }
                        Button("Export Favorites…", systemImage: "square.and.arrow.up") {
                            model.showingExporter = true
                        }
                        .disabled(model.favorites.isEmpty)
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            // The Save panel for Export. Kept on a different view from the
            // importer: SwiftUI can mix up two file panels on the same view.
            .fileExporter(isPresented: $model.showingExporter,
                          document: model.favoritesDocument,
                          contentType: .json,
                          defaultFilename: "Crystal Set Favorites") { result in
                model.exportFinished(result)
            }
            // The Now Playing bar along the bottom.
            .safeAreaInset(edge: .bottom) { MiniPlayer(player: model.player) }
            // Hands Edit mode to the list, its rows and the Edit button.
            // It comes after `.toolbar` so the Edit button uses it too.
            .environment(\.editMode, $editMode)
            // The Edit button hides when the list empties, so leave Edit mode
            // then; otherwise the next favorite would appear mid-edit.
            .onChange(of: model.favorites.isEmpty) { _, isEmpty in
                if isEmpty { editMode = .inactive }
            }
        }
    }

    // Removes the favorites at these positions (Edit mode's delete buttons).
    private func deleteFavorites(at offsets: IndexSet) {
        for station in offsets.map({ model.favorites[$0] }) {
            model.removeFromFavorites(station)
        }
    }
}

// MARK: - Search

struct SearchScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // VoiceOver reads the label "Search for"; the gray prompt
                    // inside the empty field says what it accepts.
                    TextField("Search for", text: $model.query,
                              prompt: Text("Name, tag, or stream address"))
                        .accessibilityHint("A station name or tag, or a stream address starting with http")
                        // The keyboard's Return key says "Search".
                        .submitLabel(.search)
                        .onSubmit { model.search() }
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Picker("Search by", selection: $model.field) {
                        ForEach(SearchField.allCases) { field in
                            Text(field.rawValue).tag(field)
                        }
                    }
                    Button("Search") { model.search() }
                        .disabled(model.isSearching
                                  || model.query.trimmingCharacters(in: .whitespaces).isEmpty)
                } footer: {
                    // Status such as "114 stations found."
                    if !model.searchMessage.isEmpty {
                        Text(model.searchMessage)
                    } else {
                        Text("To add a station by its address, paste it here and tap Search.")
                    }
                }

                if !model.results.isEmpty {
                    Section("Results") {
                        ForEach(model.results) { station in
                            StationRow(station: station, player: model.player, inFavorites: false)
                        }
                    }
                }

                Section {
                    Text("Station directory from radio-browser.info")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Search")
            .safeAreaInset(edge: .bottom) { MiniPlayer(player: model.player) }
        }
    }
}

// MARK: - Station row

/// One station in a list.
///
/// The whole row is one button: double-tap plays the station. Its other
/// actions are in VoiceOver's Actions rotor, in a context menu (touch and
/// hold), and as swipe actions. In Edit mode, double-tapping a favorite
/// renames it instead. (Rename is left out of the Actions rotor on purpose,
/// to keep that list short.)
struct StationRow: View {
    @EnvironmentObject private var model: AppModel
    let station: Station
    // Watched so the row can say when its station is the one playing.
    @ObservedObject var player: Player
    // Favorites rows can be moved; search result rows can't.
    let inFavorites: Bool
    // Whether the list is in Edit mode (the Edit button in the Favorites tab).
    @Environment(\.editMode) private var editMode
    // True while VoiceOver is running.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn

    // True in Edit mode on a favorite, when double-tap renames instead of plays.
    private var tapRenames: Bool { inFavorites && editMode?.wrappedValue.isEditing == true }

    // True while this row's station is the one connecting, playing or paused.
    private var isCurrent: Bool { player.station?.id == station.id && player.isActive }

    // A second line such as "The United States Of America, MP3, 128 kbps".
    private var details: String {
        [station.country, station.formatDescription].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var body: some View {
        Button {
            if tapRenames { model.renamingStation = station } else { model.play(station) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name)
                        .foregroundStyle(.primary)
                    if !details.isEmpty {
                        Text(details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isCurrent {
                    // Hidden from VoiceOver; the row's value says it in words instead.
                    Image(systemName: "speaker.wave.2.fill")
                        .accessibilityHidden(true)
                }
            }
        }
        // VoiceOver reads this after the name, e.g. "Gunsmoke, Playing".
        .accessibilityValue(isCurrent ? player.state.description : "")
        .accessibilityHint(tapRenames ? "Renames this station" : "Plays this station")
        // The Actions rotor. `if` lets an action appear only when it makes sense.
        // It changes with the mode, to keep each list short:
        //   - Favorites in Edit mode (tidying up): Move Up, Move Down, Delete.
        //     Double-tap renames. Move Up is left off the first favorite and
        //     Move Down off the last, since they can't go any further.
        //   - Otherwise (listening): the swipe action a sighted person gets
        //     (Remove on a favorite, Add to Favorites on a search result),
        //     then Stop and Sleep Timer… on the station that's playing.
        .accessibilityActions {
            if tapRenames {
                if model.favorites.first?.id != station.id {
                    Button("Move Up") { move(by: -1) }
                }
                if model.favorites.last?.id != station.id {
                    Button("Move Down") { move(by: 1) }
                }
                Button("Delete") { model.removeFromFavorites(station) }
            } else {
                // Stands in for the swipe action (see `.swipeActions` below).
                Button(swipeTitle) { swipeAction() }
                if isCurrent {
                    Button("Stop") { player.stop() }
                    Button("Sleep Timer…") { model.showingSleepTimerChoices = true }
                }
            }
        }
        // Touch and hold.
        .contextMenu {
            Button("Play", systemImage: "play") { model.play(station) }
            Button(favoriteTitle, systemImage: model.isFavorite(station) ? "star.slash" : "star") {
                toggleFavorite()
            }
            if isCurrent {
                Button("Stop", systemImage: "stop") { player.stop() }
            }
            if inFavorites {
                Button("Rename…", systemImage: "pencil") { model.renamingStation = station }
            }
        }
        // Swipe left on the row: Remove, or Add to Favorites.
        // VoiceOver would normally list a swipe action in the Actions rotor,
        // but SwiftUI listed it twice ("Remove, Remove, Activate"). So while
        // VoiceOver is on, the swipe action is left off here and the rotor
        // list above offers the same action once, with the same name.
        .swipeActions {
            if !voiceOverOn {
                if model.isFavorite(station) {
                    Button(swipeTitle, role: .destructive) { swipeAction() }
                } else {
                    Button(swipeTitle) { swipeAction() }
                        .tint(.blue)
                }
            }
        }
    }

    // The swipe action's name. "Remove", since it takes the station off
    // your list rather than deleting anything.
    private var swipeTitle: String {
        model.isFavorite(station) ? "Remove" : "Add to Favorites"
    }

    private func swipeAction() {
        if model.isFavorite(station) {
            model.removeFromFavorites(station)
        } else {
            model.addToFavorites(station)
        }
    }

    private var favoriteTitle: String {
        model.isFavorite(station) ? "Remove from Favorites" : "Add to Favorites"
    }

    private func toggleFavorite() {
        if model.isFavorite(station) {
            model.removeFromFavorites(station)
        } else {
            model.addToFavorites(station)
        }
    }

    // Selects this favorite and moves it, using the same code as the Mac's
    // Move Favorite Up and Down (which also says the new position).
    private func move(by offset: Int) {
        model.favoriteSelection = station.id
        model.moveSelectedFavorite(by: offset)
    }
}

// MARK: - Mini player

/// The Now Playing bar along the bottom of the Favorites and Search lists.
/// Double-tap pauses or resumes; the Actions rotor has Stop, Next Station,
/// Previous Station and Sleep Timer…. Hidden when nothing is playing.
struct MiniPlayer: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var player: Player

    // For example: "Playing — The Shadow".
    private var statusLine: String {
        var parts = [player.state.description]
        if !player.streamTitle.isEmpty { parts.append(player.streamTitle) }
        if let sleep = player.sleepTimerDescription { parts.append(sleep) }
        return parts.joined(separator: " — ")
    }

    private var isPlaying: Bool { player.state == .playing || player.state == .connecting }

    var body: some View {
        if let station = player.station, player.isActive {
            Button {
                player.togglePause()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(station.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(statusLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .accessibilityHidden(true)
                }
                .padding()
                // Fills the width, so the whole bar can be tapped.
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // A translucent background that keeps the list readable behind it.
            .background(.regularMaterial)
            .accessibilityLabel("Now playing: \(station.name). \(statusLine)")
            .accessibilityHint(isPlaying ? "Pauses" : "Resumes")
            .accessibilityActions {
                Button("Stop") { player.stop() }
                Button("Next Station") { model.playAdjacent(1) }
                Button("Previous Station") { model.playAdjacent(-1) }
                // Opens the sleep timer pop-up (see RootView).
                Button("Sleep Timer…") { model.showingSleepTimerChoices = true }
            }
        }
    }
}

// MARK: - Now Playing tab

/// Everything about the current station, with large, plainly labeled buttons.
struct NowPlayingScreen: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var player: Player

    private var isPlaying: Bool { player.state == .playing || player.state == .connecting }

    var body: some View {
        NavigationStack {
            // A Form is a standard grouped list of controls, like Settings.
            Form {
                Section {
                    if let station = player.station {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(station.name)
                                .font(.title2)
                            Text(player.state.description)
                                .foregroundStyle(.secondary)
                            if !player.streamTitle.isEmpty {
                                Text(player.streamTitle)
                            }
                        }
                        // VoiceOver reads the name, state and show title as one item.
                        .accessibilityElement(children: .combine)
                    } else {
                        Text("Nothing playing. Choose a station in Favorites or Search.")
                    }
                }

                Section {
                    Button(isPlaying ? "Pause" : "Resume") { player.togglePause() }
                        .disabled(player.station == nil)
                    Button("Stop") { player.stop() }
                        .disabled(!player.isActive)
                    Button("Reconnect") { player.reconnect() }
                        .disabled(player.station == nil)
                }

                Section {
                    Button("Next Station") { model.playAdjacent(1) }
                    Button("Previous Station") { model.playAdjacent(-1) }
                } footer: {
                    Text("Steps through Favorites or Search results, whichever you used last.")
                }

                Section {
                    SleepTimerPicker(player: player)
                    if let sleep = player.sleepTimerDescription {
                        Text(sleep)
                    }
                } footer: {
                    Text("The sound fades out over the last 30 seconds, then playback stops.")
                }
            }
            .navigationTitle("Now Playing")
        }
    }
}

// MARK: - Sleep timer picker

/// The sleep timer choices: Off, 15 minutes, 30 minutes, and so on.
/// Used in the Now Playing tab and in the Favorites tab's More menu. Inside
/// a menu it becomes a submenu; in a Form it's a standard picker row.
struct SleepTimerPicker: View {
    @ObservedObject var player: Player

    var body: some View {
        Picker("Sleep Timer", systemImage: "moon.zzz", selection: Binding(
            get: { player.sleepTimerMinutes },
            set: { player.setSleepTimer(minutes: $0) }
        )) {
            Text("Off").tag(0)
            ForEach(Player.sleepTimerChoices, id: \.self) { minutes in
                Text("\(minutes) minutes").tag(minutes)
            }
        }
        .pickerStyle(.menu)
    }
}
