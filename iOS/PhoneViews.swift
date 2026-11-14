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
        // The app's blue (buttons such as Search, Pause and Stop), a little
        // darker than standard blue so it passes the accessibility contrast
        // guideline; see Color.accessibleTint below.
        .tint(Color.accessibleTint)
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
                    // The stations to list: all favorites, or only those
                    // matching the Filter field.
                    let stations = model.filteredFavorites
                    List {
                        // The pinned stations, as large buttons above the list.
                        // Hidden while filtering (the filter is for finding
                        // something else) and in Edit mode (for tidying the list).
                        // The section's "Pinned" header is a heading, so
                        // VoiceOver's Headings rotor jumps straight to it.
                        if showsPinned {
                            Section("Pinned") {
                                PinnedStations(player: model.player)
                            }
                        }
                        Section(showsPinned ? "All Favorites" : "") {
                            ForEach(stations) { station in
                                StationRow(station: station, player: model.player, inFavorites: true)
                            }
                            // In Edit mode, drag handles reorder and delete buttons
                            // remove. Moving is off while filtering, since a place
                            // in the filtered list isn't a place in the real one.
                            .onMove(perform: model.isFilteringFavorites ? nil : { from, to in
                                model.favorites.move(fromOffsets: from, toOffset: to)
                            })
                            // The delete buttons are attached only in Edit mode (nil
                            // means none). Otherwise iOS also adds its own swipe-to-
                            // delete, which put a second Delete in VoiceOver's Actions
                            // rotor beside the row's own Remove swipe action.
                            .onDelete(perform: editMode.isEditing ? { offsets in
                                for station in offsets.map({ stations[$0] }) {
                                    model.removeFromFavorites(station)
                                }
                            } : nil)
                        }
                        if stations.isEmpty {
                            Text("No favorites match \u{201C}\(model.favoritesFilter)\u{201D}.")
                                .foregroundStyle(Color.detailText)
                        }
                    }
                    // The Filter field, always shown at the top of the list
                    // (not hidden until you pull down, so VoiceOver finds it).
                    .searchable(text: $model.favoritesFilter,
                                placement: .navigationBarDrawer(displayMode: .always),
                                prompt: "Filter favorites")
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

    // Whether to show the Pinned section.
    private var showsPinned: Bool {
        !model.pinnedStations.isEmpty && !model.isFilteringFavorites && !editMode.isEditing
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
                            .foregroundStyle(Color.detailText)
                    } else {
                        Text("To add a station by its address, paste it here and tap Search.")
                            .foregroundStyle(Color.detailText)
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
                        .foregroundStyle(Color.detailText)
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

    // A second line such as "United States · MP3 · 128 kbps".
    private var details: String { station.detailLine }

    var body: some View {
        Button {
            if tapRenames { model.renamingStation = station } else { model.play(station) }
        } label: {
            HStack(spacing: 12) {
                // The station's logo, or a colored tile (hidden from VoiceOver).
                StationArtwork(station: station, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name)
                        .foregroundStyle(.primary)
                    if !details.isEmpty {
                        Text(details)
                            .font(.subheadline)
                            .foregroundStyle(Color.detailText)
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
        // Show the station name in the normal text color (black, or white in
        // Dark Mode). Inside a list, iOS colors a button's text with the app's
        // tint, standard blue, which measures about 4:1 against white: under
        // the 4.5:1 that accessibility guidelines ask for. Apple's audit
        // flagged every name. The row is still a button to VoiceOver, Voice
        // Control and Switch Control.
        .tint(.primary)
        // VoiceOver reads this after the name, e.g. "Gunsmoke, Playing".
        .accessibilityValue(isCurrent ? player.state.description : "")
        .accessibilityHint(tapRenames ? "Renames this station" : "Plays this station")
        // The Actions rotor. `if` lets an action appear only when it makes sense.
        // It changes with the mode, to keep each list short:
        //   - Favorites in Edit mode (tidying up): Move Up, Move Down, Delete.
        //     Double-tap renames. Move Up is left off the first favorite and
        //     Move Down off the last, since they can't go any further.
        //   - Otherwise (listening): see ListeningActions, below.
        .accessibilityActions {
            if tapRenames {
                if model.favorites.first?.id != station.id {
                    Button("Move Up") { move(by: -1) }
                }
                if model.favorites.last?.id != station.id {
                    Button("Move Down") { move(by: 1) }
                }
                Button("Delete") { model.removeFromFavorites(station) }
            }
        }
        // Remove (or Add to Favorites), Pin to Top or Unpin, then Stop and
        // Sleep Timer… on the station that's playing. Shared with the pinned
        // buttons, so the Actions rotor is the same wherever a station shows.
        .modifier(ListeningActions(station: station, player: player, active: !tapRenames))
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
                Button(model.isPinned(station) ? "Unpin" : "Pin to Top",
                       systemImage: model.isPinned(station) ? "pin.slash" : "pin") {
                    model.togglePin(station)
                }
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

// MARK: - Shared Actions rotor

/// The Actions rotor (VoiceOver: swipe up or down) for a station while
/// listening, shared by list rows and pinned buttons so it's the same
/// wherever a station appears:
///   - Remove (a favorite) or Add to Favorites (a search result), standing in
///     for the swipe action a sighted person gets.
///   - Pin to Top or Unpin, for favorites.
///   - Stop and Sleep Timer…, on the station that's playing.
/// `active` is false in Edit mode, where a row offers Move Up, Move Down and
/// Delete instead.
struct ListeningActions: ViewModifier {
    @EnvironmentObject private var model: AppModel
    let station: Station
    @ObservedObject var player: Player
    var active = true

    private var isCurrent: Bool { player.station?.id == station.id && player.isActive }

    func body(content: Content) -> some View {
        content.accessibilityActions {
            if active {
                if model.isFavorite(station) {
                    Button("Remove") { model.removeFromFavorites(station) }
                    Button(model.isPinned(station) ? "Unpin" : "Pin to Top") { model.togglePin(station) }
                } else {
                    Button("Add to Favorites") { model.addToFavorites(station) }
                }
                if isCurrent {
                    Button("Stop") { player.stop() }
                    Button("Sleep Timer…") { model.showingSleepTimerChoices = true }
                }
            }
        }
    }
}

// MARK: - Pinned stations

/// Up to ten pinned favorites as large buttons, in a grid that fits the
/// screen: two across on an iPhone, more on an iPad or in landscape, and one
/// full-width button per row at the largest text sizes.
struct PinnedStations: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var player: Player
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        // `.adaptive` fits as many columns as there's room for, each at least
        // this wide. At the Accessibility text sizes, a button per row.
        let minimum: CGFloat = textSize.isAccessibilitySize ? 600 : 150
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 10)], spacing: 10) {
            ForEach(model.pinnedStations) { station in
                PinnedStationButton(station: station, player: player)
            }
        }
        // The buttons sit straight on the page, each its own card, instead of
        // inside the list's white box. (Inside it, in Dark Mode, the buttons
        // were the same color as the box and didn't look like buttons.)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }
}

/// One pinned station: double-tap (or tap) plays it. VoiceOver reads its name,
/// "Playing" when it's the one on, and offers the same Actions rotor as the
/// station's row in the list.
struct PinnedStationButton: View {
    @EnvironmentObject private var model: AppModel
    let station: Station
    @ObservedObject var player: Player
    @Environment(\.dynamicTypeSize) private var textSize

    private var isCurrent: Bool { player.station?.id == station.id && player.isActive }

    var body: some View {
        Button {
            model.play(station)
        } label: {
            HStack(spacing: 10) {
                StationArtwork(station: station, size: 40)
                Text(station.name)
                    .font(.headline)
                    // Long names wrap to as many lines as they need. (A three-
                    // line limit cut names off at larger text sizes.)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            // The same card color as the list below (white, or dark gray in
            // Dark Mode), on the page's gray, so each button stands out.
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12))
            // The playing station gets an outline in the app's blue. (A
            // speaker icon, as in the list, left too little room for names.)
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accessibleTint, lineWidth: 2.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        // Several buttons share one list row; .plain keeps a tap on one from
        // pressing them all.
        .buttonStyle(.plain)
        .accessibilityValue(isCurrent ? player.state.description : "")
        .accessibilityHint("Plays this station")
        .modifier(ListeningActions(station: station, player: player))
        .contextMenu {
            Button("Play", systemImage: "play") { model.play(station) }
            Button("Unpin", systemImage: "pin.slash") { model.togglePin(station) }
            Button("Remove from Favorites", systemImage: "star.slash") { model.removeFromFavorites(station) }
            if isCurrent {
                Button("Stop", systemImage: "stop") { player.stop() }
            }
        }
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
                    StationArtwork(station: station, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(station.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(statusLine)
                            .font(.subheadline)
                            .foregroundStyle(Color.detailText)
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
            // A solid background, so the bar's text always sits on the same
            // color. (It used to be translucent "material", which let the list
            // scrolling behind it show through. Apple's accessibility audit
            // found the station name too faint against that at the largest
            // text sizes.) The thin line on top separates it from the list.
            .background(Color(uiColor: .secondarySystemBackground))
            .overlay(alignment: .top) { Divider() }
            // At the largest text sizes the bar used to grow until it covered
            // most of the list. Like the tab bar, it now stops growing at the
            // largest standard size, and touching and holding it shows its
            // text enlarged in the middle of the screen instead (the Large
            // Content Viewer, which works at the Accessibility text sizes).
            // VoiceOver reads the full text either way, and the Now Playing
            // tab shows everything at full size.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityShowsLargeContentViewer {
                Text("\(station.name)\n\(statusLine)")
            }
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

/// Everything about the current station: its logo, name and show, large
/// playback controls, and the sleep timer.
///
/// The controls keep the same names as always ("Pause" or "Resume", "Stop",
/// "Reconnect", "Next Station", "Previous Station", "Sleep Timer"), so
/// VoiceOver, Voice Control and Switch Control work as before; only the look
/// is new. At the Accessibility text sizes the controls stack up instead of
/// sitting side by side, and on an iPad the content keeps a comfortable width.
struct NowPlayingScreen: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var player: Player
    @Environment(\.dynamicTypeSize) private var textSize

    private var isPlaying: Bool { player.state == .playing || player.state == .connecting }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    if player.station != nil {
                        controls
                    }
                    sleepTimer
                }
                .padding()
                // A comfortable width on an iPad or a wide window.
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Now Playing")
        }
    }

    // The logo, then the station, show and state. VoiceOver reads the text as
    // one item, such as "Gunsmoke. Playing. The Shadow".
    private var header: some View {
        VStack(spacing: 16) {
            StationArtwork(station: player.station, size: textSize.isAccessibilitySize ? 140 : 220)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
            VStack(spacing: 6) {
                if let station = player.station {
                    Text(station.name)
                        .font(.title2.bold())
                    if !player.streamTitle.isEmpty {
                        Text(player.streamTitle)
                            .font(.headline)
                    }
                    HStack(spacing: 6) {
                        // The level meter shows only for a station that's on.
                        if [.playing, .connecting, .paused].contains(player.state) {
                            LiveIndicator(active: player.state == .playing)
                        }
                        Text(player.state.description)
                            .foregroundStyle(Color.detailText)
                    }
                } else {
                    Text("Nothing playing")
                        .font(.title2.bold())
                    Text("Choose a station in Favorites or Search.")
                        .foregroundStyle(Color.detailText)
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
        }
    }

    // Previous, Play/Pause and Next in a row (a column at the largest text
    // sizes), with Stop and Reconnect below.
    private var controls: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 16))
                                                  : AnyLayout(HStackLayout(spacing: 36))
        return VStack(spacing: 20) {
            layout {
                Button { model.playAdjacent(-1) } label: {
                    Image(systemName: "backward.fill").font(.title)
                        .frame(minWidth: 56, minHeight: 56)
                }
                .accessibilityLabel("Previous Station")

                Button { player.togglePause() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(Circle().fill(Color.accessibleTint))
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Resume")

                Button { model.playAdjacent(1) } label: {
                    Image(systemName: "forward.fill").font(.title)
                        .frame(minWidth: 56, minHeight: 56)
                }
                .accessibilityLabel("Next Station")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accessibleTint)

            Text("Previous and Next step through Favorites or Search results, whichever you used last.")
                .font(.footnote)
                .foregroundStyle(Color.detailText)
                .multilineTextAlignment(.center)

            let secondary = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12))
                                                         : AnyLayout(HStackLayout(spacing: 12))
            secondary {
                Button { player.stop() } label: {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .disabled(!player.isActive)
                Button { player.reconnect() } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // Links the visible "Sleep Timer" label to its menu for VoiceOver.
    @Namespace private var sleepTimerPair

    // The sleep timer, on a card.
    private var sleepTimer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // `accessibilityLabeledPair` tells VoiceOver this label names the
                // menu beside it, so the two read as one item ("Sleep Timer,
                // Off"). Hiding the label instead made Apple's audit report
                // visible text VoiceOver couldn't reach.
                Label("Sleep Timer", systemImage: "moon.zzz")
                    .accessibilityLabeledPair(role: .label, id: "sleepTimer", in: sleepTimerPair)
                Spacer()
                SleepTimerPicker(player: player)
                    .accessibilityLabeledPair(role: .content, id: "sleepTimer", in: sleepTimerPair)
            }
            if let sleep = player.sleepTimerDescription {
                Text(sleep)
            }
            Text("The sound fades out over the last 30 seconds, then playback stops.")
                .font(.footnote)
                .foregroundStyle(Color.detailText)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Three small bars that rise and fall while a station plays, like a level
/// meter. Still when paused, and always still with Reduce Motion on. Only for
/// the eye: the words beside it ("Playing") say the same thing.
struct LiveIndicator: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var high = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { bar in
                Capsule()
                    .fill(Color(red: 0.72, green: 0.42, blue: 0.20))   // the icon's copper
                    .frame(width: 3, height: barHeight(bar))
            }
        }
        .frame(height: 14, alignment: .bottom)
        .accessibilityHidden(true)
        .onAppear { animate() }
        .onChange(of: active) { _, _ in animate() }
    }

    private func barHeight(_ bar: Int) -> CGFloat {
        guard active else { return 4 }
        let heights: [[CGFloat]] = [[6, 14], [12, 5], [8, 12]]
        return heights[bar][high ? 1 : 0]
    }

    private func animate() {
        guard active, !reduceMotion else { high = false; return }
        withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { high = true }
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

// MARK: - Colors

extension Color {
    /// Gray text for second lines (country and format, status, notes) that
    /// is still easy to read.
    ///
    /// Why not Apple's standard `.secondary` gray: on a white background it
    /// measures about 4:1 against the page. That's below the 4.5:1 that
    /// accessibility guidelines (WCAG AA) ask for, and Apple's own
    /// accessibility audit flagged every second line in the app. These grays
    /// measure about 8.5:1 in Light Mode and over 10:1 in Dark Mode, but
    /// still look lighter than the main text, so the two lines stay distinct.
    ///
    /// A UIColor with a "provider" picks its value each time it's drawn, so it
    /// follows Light and Dark Mode as they change.
    /// The app's tint (button text such as Search, Pause and Stop).
    ///
    /// Standard iOS blue measures about 4:1 against white, a little under the
    /// 4.5:1 guideline; Apple's audit flagged every blue button. This darker
    /// blue measures about 5.7:1 in Light Mode. Dark Mode keeps the standard
    /// dark-mode blue, which already passes (about 5.4:1 on black).
    static let accessibleTint = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1)
            : UIColor(red: 0.0, green: 0.38, blue: 0.80, alpha: 1)
    })

    static let detailText = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.78, alpha: 1)
            : UIColor(white: 0.30, alpha: 1)
    })
}
