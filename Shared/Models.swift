// Models.swift
//
// The app's data and the decisions it makes. This file has no screens in it,
// and both the Mac and iPhone versions use it.
// It holds:
//   - Station: what the app knows about one radio station.
//   - RadioBrowserClient: talks to the free Radio Browser station directory
//     on the internet to search for stations.
//   - announce(_:): makes VoiceOver speak a short message.
//   - AppModel: the app's "brain". It keeps the favorites list, the search
//     results, what's selected, and handles actions such as play, add to
//     favorites, and search. The screens (ContentView.swift) read from it
//     and call it; they don't make decisions themselves.
//
// See docs/HOW-IT-WORKS.md for a guided tour of the whole app.

// "import" brings in code Apple provides. Foundation has the basics
// (text, dates, files, networking). AppKit (Mac) and UIKit (iPhone) are
// each platform's user interface toolkit; they're needed here only for
// VoiceOver announcements.
import Foundation
// MediaPlayer provides the Next and Previous Track commands used by the
// lock screen, Control Center and headphones.
import MediaPlayer
// `#if os(macOS)` includes the lines up to `#else` only when building for
// the Mac; the lines after `#else` are used for the iPhone instead.
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Station

/// One radio station.
///
/// A `struct` is a bundle of related values. The words after the colon say
/// what a Station can do:
/// - `Codable`: can be saved to and loaded from JSON files.
/// - `Identifiable`: has an `id` that tells stations apart, which lists need.
/// - `Hashable`: can be compared and stored in sets.
struct Station: Codable, Identifiable, Hashable {
    // `var` means the value can change. Each line is one piece of information.
    var id: String
    var name: String
    /// The stream address, for example "http://example.com:8000/stream".
    var url: String
    var country: String
    /// Descriptive words such as "old time radio, drama", separated by commas.
    var tags: String
    /// The audio format, such as "MP3" or "AAC".
    var codec: String
    /// The stream's quality in kilobits per second (0 when unknown).
    var bitrate: Int

    /// Radio Browser stations use its station UUID as their ID. Stations added
    /// by hand or imported from a file get a prefixed ID instead.
    ///
    /// This is a "computed property": it has no stored value of its own and is
    /// worked out from `id` each time it's read.
    var isFromRadioBrowser: Bool { !(id.hasPrefix("manual-") || id.hasPrefix("import-")) }

    /// Text for the Format column, such as "MP3, 128 kbps".
    var formatDescription: String {
        var parts: [String] = []
        if !codec.isEmpty { parts.append(codec) }
        if bitrate > 0 { parts.append("\(bitrate) kbps") }
        return parts.joined(separator: ", ")
    }
}

/// Shape of a station as returned by the Radio Browser API.
///
/// The names here must match the names in Radio Browser's JSON exactly, which
/// is why one is spelled `url_resolved`. A `?` after a type means the value
/// may be missing (Swift calls this an "optional").
struct APIStation: Decodable {
    // `let` means the value never changes once set.
    let stationuuid: String
    let name: String?
    let url: String?
    /// The final stream address after Radio Browser has followed any redirects.
    let url_resolved: String?
    let country: String?
    let tags: String?
    let codec: String?
    let bitrate: Int?

    /// Converts Radio Browser's version of a station into the app's own Station,
    /// filling in blanks for anything missing.
    var station: Station {
        // `??` means "or, if that's missing, use this instead".
        let resolved = url_resolved ?? ""
        return Station(
            id: stationuuid,
            name: (name ?? "Unnamed station").trimmingCharacters(in: .whitespacesAndNewlines),
            // Prefer the resolved address; fall back to the original one.
            url: resolved.isEmpty ? (url ?? "") : resolved,
            country: country ?? "",
            // Radio Browser sends "drama,otr"; add spaces so it reads "drama, otr".
            tags: (tags ?? "").replacingOccurrences(of: ",", with: ", "),
            codec: codec ?? "",
            bitrate: bitrate ?? 0
        )
    }
}

/// What the search looks at: station tags or station names.
///
/// An `enum` is a fixed list of choices. The text after each `=` is what the
/// Search by pop-up button shows.
enum SearchField: String, CaseIterable, Identifiable {
    case tag = "Tag"
    case name = "Name"
    var id: String { rawValue }
}

// MARK: - Radio Browser client

/// Searches the Radio Browser directory (https://www.radio-browser.info).
///
/// An `actor` is like a class that only does one thing at a time, so two
/// searches running at once can't trip over each other's data.
actor RadioBrowserClient {
    /// One entry in Radio Browser's list of mirror servers.
    private struct Server: Decodable { let name: String }

    /// The mirror server chosen for this session (nil until the first search).
    private var baseURL: URL?
    /// Apple's networking object, set up once and reused for every request.
    private let session: URLSession

    // `init` runs when a new RadioBrowserClient is created.
    init() {
        let config = URLSessionConfiguration.default
        // Radio Browser asks apps to identify themselves by name.
        config.httpAdditionalHeaders = ["User-Agent": "CrystalSet/1.0"]
        // Give up on a request after 20 seconds.
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    /// Radio Browser asks clients to pick one of its mirror servers.
    ///
    /// `async` means this function can wait (here, for the network) without
    /// freezing the app.
    private func server() async -> URL {
        // Already picked one? Keep using it.
        if let baseURL { return baseURL }
        // A known server to fall back on if the list can't be fetched.
        var chosen = URL(string: "https://de1.api.radio-browser.info")!
        // Fetch the list of servers and pick one at random. Each `let` line
        // must succeed for the block to run; if any fails, the fallback stays.
        if let listURL = URL(string: "https://all.api.radio-browser.info/json/servers"),
           let result = try? await session.data(from: listURL),
           let servers = try? JSONDecoder().decode([Server].self, from: result.0),
           let pick = Set(servers.map(\.name)).randomElement(),
           let url = URL(string: "https://\(pick)") {
            chosen = url
        }
        baseURL = chosen
        return chosen
    }

    /// Searches for stations whose tag or name contains `text`.
    ///
    /// `throws` means this can fail with an error (for example, no internet),
    /// which the caller must handle.
    func search(_ text: String, by field: SearchField) async throws -> [Station] {
        let base = await server()
        // Build the web address, such as
        // https://<server>/json/stations/search?tag=otr&hidebroken=true&...
        var components = URLComponents(url: base.appendingPathComponent("json/stations/search"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: field == .tag ? "tag" : "name", value: text),
            // Leave out stations Radio Browser knows are broken.
            URLQueryItem(name: "hidebroken", value: "true"),
            // Most-played stations first.
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
            // At most 200 results.
            URLQueryItem(name: "limit", value: "200"),
        ]
        // Send the request and wait for the reply.
        let (data, response) = try await session.data(from: components.url!)
        // Status codes from 200 to 299 mean success.
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // Try a different mirror next time.
            baseURL = nil
            throw URLError(.badServerResponse)
        }
        // Convert the JSON reply into Stations, dropping any without a stream
        // address and any duplicates. `seen` remembers IDs already kept.
        var seen = Set<String>()
        return try JSONDecoder().decode([APIStation].self, from: data)
            .map(\.station)
            .filter { !$0.url.isEmpty && seen.insert($0.id).inserted }
    }

    /// Tells Radio Browser a station was played (helps its popularity ranking).
    func countClick(_ stationID: String) async {
        let base = await server()
        // `_ =` and `try?` mean: send it, and ignore the reply or any error.
        _ = try? await session.data(from: base.appendingPathComponent("json/url/\(stationID)"))
    }
}

// MARK: - VoiceOver announcements

/// Asks VoiceOver to speak `text`, such as "Added Gunsmoke to favorites".
///
/// `@MainActor` means this runs on the main thread, where all user interface
/// work must happen. If VoiceOver is off, nothing happens.
@MainActor
func announce(_ text: String) {
    #if os(macOS)
    NSAccessibility.post(
        element: NSApp as Any,
        notification: .announcementRequested,
        userInfo: [
            .announcement: text,
            // High priority: speak it even if VoiceOver is in the middle of something.
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ]
    )
    #else
    // The iPhone's version. The attribute marks it high priority, as above.
    let message = NSAttributedString(
        string: text,
        attributes: [.accessibilitySpeechAnnouncementPriority: UIAccessibilityPriority.high]
    )
    UIAccessibility.post(notification: .announcement, argument: message)
    #endif
}

// MARK: - App model

/// The app's state and actions. There is one AppModel for the whole app,
/// created in CrystalSetApp.swift.
///
/// A `class` (unlike a struct) is shared: every screen that uses the AppModel
/// sees the same one. `ObservableObject` lets screens watch it. When a
/// `@Published` value changes, SwiftUI redraws whatever shows that value.
@MainActor
final class AppModel: ObservableObject {
    /// The two tabs in the main window.
    enum Tab: Hashable { case favorites, search }

    // What the window is showing.
    @Published var tab: Tab = .favorites

    // The favorites list. `didSet` runs every time the list changes, so it's
    // saved to disk after every add, remove, or move.
    @Published var favorites: [Station] = [] { didSet { saveFavorites() } }
    // The selected favorite's ID, or nil when nothing is selected.
    @Published var favoriteSelection: Station.ID?

    // Search results and the selected result.
    @Published var results: [Station] = []
    @Published var searchSelection: Station.ID?
    // The search text. This is the search the app starts with.
    @Published var query = "old time radio"
    @Published var field: SearchField = .tag
    @Published var isSearching = false
    // Status text shown under the search field, such as "114 stations found."
    @Published var searchMessage = ""

    // These switch sheets, file panels and alerts on and off. Setting one to
    // true makes the window show it (see ContentView.swift).
    /// The favorite being renamed, or nil. Setting it opens the Rename
    /// sheet on the Mac, or the Rename alert on the iPhone.
    @Published var renamingStation: Station?
    @Published var showingImporter = false
    @Published var showingImportResult = false
    @Published var showingExporter = false
    /// iPhone only: the pop-up list of sleep timer lengths, opened from
    /// the "Sleep Timer…" item in VoiceOver's Actions rotor.
    @Published var showingSleepTimerChoices = false
    /// Title of the alert that reports an import or export result.
    var resultTitle = "Import Favorites"
    // Set to true to move the cursor into the search field (Command-F).
    @Published var focusSearchField = false
    /// True while a text field has focus, so arrow-key menu shortcuts
    /// (Command-Left/Right/Up/Down) go to the text field instead.
    @Published var isEditingText = false
    // The message shown in the import or export result alert.
    var importMessage = ""

    // The audio player (Player.swift) and the station directory client.
    let player = Player()
    private let client = RadioBrowserClient()

    /// Where favorites are saved:
    /// ~/Library/Application Support/Crystal Set/favorites.json
    private var favoritesFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Crystal Set", isDirectory: true)
        // Make the folder if it doesn't exist yet.
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("favorites.json")

        // The app was first released as "OTR Tuner". Copy favorites saved
        // under that name the first time, leaving the original in place.
        let oldFile = support.appendingPathComponent("OTR Tuner/favorites.json")
        if !FileManager.default.fileExists(atPath: file.path),
           FileManager.default.fileExists(atPath: oldFile.path) {
            try? FileManager.default.copyItem(at: oldFile, to: file)
        }
        return file
    }

    // Runs once when the app starts: loads saved favorites, if there are any.
    init() {
        if let data = try? Data(contentsOf: favoritesFile),
           let saved = try? JSONDecoder().decode([Station].self, from: data) {
            favorites = saved
            favoriteSelection = saved.first?.id
        }
        setUpTrackCommands()
    }

    // MARK: Next and Previous from outside the app

    /// Turns on Next Track and Previous Track for the lock screen, Control
    /// Center, headphones and the keyboard's media keys.
    ///
    /// Why here and not in Player.swift with Play and Pause: the Player plays
    /// one station and doesn't know about any list. Choosing the "next"
    /// station needs the favorites (or search results), and those live here.
    ///
    /// iOS dims any button whose command has no target ("addTarget"), which
    /// is why Next and Previous were greyed out on the lock screen before.
    ///
    /// Headphones send the same commands: on AirPods and wired EarPods a
    /// double press is Next Track and a triple press is Previous Track.
    private func setUpTrackCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        // These targets run on the main thread already, but Swift can't
        // know that, so `assumeIsolated` says so (it would stop if wrong).
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.playAdjacentFromRemote(+1) }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.playAdjacentFromRemote(-1) }
            return .success
        }
    }

    /// Next (+1) or previous (-1) station, for the lock screen and headphones.
    ///
    /// This is different from playAdjacent (Command-Arrow), which steps through
    /// the selected row in the tab on screen. From the lock screen you can't
    /// see the screen, so this steps from the *playing* station, through
    /// whichever list it's in (favorites first). Both wrap around from the
    /// last station to the first, so a press always plays something instead of
    /// silently doing nothing at the end of the list.
    private func playAdjacentFromRemote(_ offset: Int) {
        let playingID = player.station?.id
        let list: [Station]
        if let playingID, results.contains(where: { $0.id == playingID }),
           !favorites.contains(where: { $0.id == playingID }) {
            list = results
        } else {
            list = favorites
        }
        guard !list.isEmpty else { return }
        let index = playingID.flatMap { id in list.firstIndex { $0.id == id } }
        // With nothing playing from this list, start at the first (or last) station.
        let next = index.map { ($0 + offset + list.count) % list.count }
            ?? (offset > 0 ? 0 : list.count - 1)
        if list == favorites { favoriteSelection = list[next].id } else { searchSelection = list[next].id }
        player.play(list[next])
        if list[next].isFromRadioBrowser {
            let id = list[next].id
            Task { await client.countClick(id) }
        }
    }

    // Writes the favorites list to disk as JSON. ".atomic" writes to a
    // temporary file first, so a crash can't leave a half-written file.
    private func saveFavorites() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(favorites) {
            try? data.write(to: favoritesFile, options: .atomic)
        }
    }

    // MARK: Selection

    /// The station selected in whichever tab is showing, or nil.
    var selectedStation: Station? {
        switch tab {
        case .favorites:
            // `first { ... }` finds the first station that matches the test in braces.
            // `$0` means "the item being tested".
            return favorites.first { $0.id == favoriteSelection }
        case .search:
            return results.first { $0.id == searchSelection }
        }
    }

    func isFavorite(_ station: Station) -> Bool {
        favorites.contains { $0.id == station.id }
    }

    // MARK: Playback

    /// Plays a station, and tells Radio Browser it was played.
    func play(_ station: Station) {
        // Select the station in the list it was played from, so Next and
        // Previous Station step from it. (On iPhone you tap a row to play it
        // without selecting it first.)
        if currentList.contains(where: { $0.id == station.id }) {
            currentSelection = station.id
        }
        player.play(station)
        if station.isFromRadioBrowser {
            // `Task { }` runs work in the background so the app doesn't wait for it.
            Task { await client.countClick(station.id) }
        }
    }

    // Command-Return.
    func playSelected() {
        if let station = selectedStation { play(station) }
    }

    /// Plays the station, or pauses and resumes it if it's the one already playing.
    /// Used by the Space bar in a station table.
    func playOrPause(_ station: Station) {
        // `guard` checks a condition and leaves the function early if it fails.
        // Here: if a different station is playing, just play this one.
        guard player.station?.id == station.id else {
            play(station)
            return
        }
        switch player.state {
        case .playing, .connecting, .paused:
            player.togglePause()
        case .stopped, .failed:
            play(station)
        }
    }

    /// The list shown in the current tab, and its selection.
    private var currentList: [Station] { tab == .favorites ? favorites : results }

    // Reads or changes the selection in whichever tab is showing.
    private var currentSelection: Station.ID? {
        get { tab == .favorites ? favoriteSelection : searchSelection }
        set {
            if tab == .favorites { favoriteSelection = newValue } else { searchSelection = newValue }
        }
    }

    /// Plays the next (+1) or previous (-1) station in the current tab's list.
    /// Command-Right Arrow and Command-Left Arrow.
    func playAdjacent(_ offset: Int) {
        let list = currentList
        guard !list.isEmpty else {
            announce(tab == .favorites ? "No favorites" : "No search results")
            return
        }
        // Start from the selected station, or else the playing one.
        let anchor = currentSelection ?? player.station?.id
        // Find that station's position in the list (0 is the first).
        let index = anchor.flatMap { id in list.firstIndex { $0.id == id } }
        // Step from it, wrapping around at the ends: Next on the last station
        // goes to the first, and Previous on the first goes to the last, so
        // you can keep pressing without having to turn back.
        // `%` is the remainder after dividing. Adding list.count first keeps
        // the number from going below zero when stepping back from the first
        // station (0 - 1 + count = count - 1, the last station).
        // With nothing to start from, go to the first or last station.
        let next = index.map { ($0 + offset + list.count) % list.count }
            ?? (offset > 0 ? 0 : list.count - 1)
        currentSelection = list[next].id
        play(list[next])
    }

    /// Selects the playing station in Favorites (or Search results) and shows that tab.
    /// Command-L.
    func showCurrentStation() {
        guard let station = player.station else {
            announce("Nothing playing")
            return
        }
        if favorites.contains(where: { $0.id == station.id }) {
            tab = .favorites
            favoriteSelection = station.id
        } else if results.contains(where: { $0.id == station.id }) {
            tab = .search
            searchSelection = station.id
        } else {
            announce("\(station.name) is not in Favorites or Search results")
            return
        }
        announce("Selected \(station.name)")
    }

    /// Changes the volume by `step` (0.05 is 5%) and speaks the new level.
    /// Command-Up Arrow and Command-Down Arrow.
    func changeVolume(by step: Double) {
        // Rounded to 5% so repeated presses land on 0%, 5%, 10%, … 100%.
        // Volume runs from 0 (silent) to 1 (full); min and max keep it in that range.
        let newVolume = min(1, max(0, ((player.volume + step) * 20).rounded() / 20))
        player.volume = newVolume
        announce("Volume \(Int((newVolume * 100).rounded())) percent")
    }

    // MARK: Favorites

    func addToFavorites(_ station: Station) {
        guard !isFavorite(station) else {
            announce("\(station.name) is already a favorite")
            return
        }
        favorites.append(station)
        announce("Added \(station.name) to favorites")
    }

    func removeFromFavorites(_ station: Station) {
        guard let index = favorites.firstIndex(where: { $0.id == station.id }) else { return }
        favorites.remove(at: index)
        // If the removed station was selected, select the one that took its
        // place (or the new last one), so the selection doesn't vanish.
        if favoriteSelection == station.id {
            favoriteSelection = favorites.isEmpty ? nil : favorites[min(index, favorites.count - 1)].id
        }
        announce("Removed \(station.name) from favorites")
    }

    // Command-D: adds the selected station, or removes it if it's already a favorite.
    func toggleFavoriteForSelection() {
        guard let station = selectedStation else { return }
        if isFavorite(station) { removeFromFavorites(station) } else { addToFavorites(station) }
    }

    /// Moves the selected favorite up (-1) or down (+1) one place.
    func moveSelectedFavorite(by offset: Int) {
        guard let id = favoriteSelection,
              let i = favorites.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard favorites.indices.contains(j) else { return }
        favorites.swapAt(i, j)
        // People count from 1, so add 1 to the position.
        announce("Position \(j + 1) of \(favorites.count)")
    }

    /// Gives a favorite a new name. An empty name is ignored.
    func renameFavorite(_ station: Station, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = favorites.firstIndex(where: { $0.id == station.id }) else { return }
        favorites[index].name = name
        // If it's the station playing, the Now Playing bar shows the new name too.
        player.stationRenamed(favorites[index])
        announce("Renamed to \(name)")
    }

    /// Starts adding a station by its address (File > Add Station…, Command-N).
    /// There's no separate form: the Search field takes addresses too, so
    /// this shows Search with an empty field, ready to paste into.
    func startAddingStation() {
        tab = .search
        query = ""
        focusSearchField = true
    }

    // MARK: Search

    /// Searches Radio Browser for `query` and fills in `results`.
    /// If `query` is a stream address instead, shows that one station.
    func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Do nothing for an empty search, or if a search is already running.
        guard !text.isEmpty, !isSearching else { return }
        // Anything starting with http:// or https:// is an address, not a search.
        let lowered = text.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            lookUpAddress(text)
            return
        }
        isSearching = true
        searchMessage = "Searching…"
        Task {
            // `do` / `catch`: try the search; if it throws an error, the
            // `catch` part runs instead.
            do {
                let found = try await client.search(text, by: field)
                results = found
                searchSelection = found.first?.id
                searchMessage = found.isEmpty ? "No stations found." : "\(found.count) stations found."
            } catch {
                searchMessage = "Search failed: \(error.localizedDescription)"
            }
            isSearching = false
            announce(searchMessage)
        }
    }

    /// Shows a stream address as a single search result, so it can be played
    /// to try it, then added to Favorites like any other result.
    ///
    /// The station is named after what the stream calls itself (see
    /// StreamResolver.stationName), or else the address's server name, such
    /// as "radio.example.com". Rename it later in Favorites.
    private func lookUpAddress(_ address: String) {
        // The same check Player uses: an http or https address with a server name.
        guard let url = URL(string: address), url.host != nil else {
            results = []
            searchMessage = "That isn't a valid stream address."
            announce(searchMessage)
            return
        }
        // Already a favorite? Show that one, so it isn't added twice.
        if let existing = favorites.first(where: { $0.url == address }) {
            results = [existing]
            searchSelection = existing.id
            searchMessage = "This address is already in Favorites as \(existing.name)."
            announce(searchMessage)
            return
        }
        isSearching = true
        searchMessage = "Checking address…"
        Task {
            // A playlist link (.pls, .m3u) is opened to find the stream inside,
            // since that's what reports the station's name.
            let streamURL = await StreamResolver.resolve(address) ?? url
            let name = await StreamResolver.stationName(at: streamURL) ?? url.host ?? address
            let station = Station(
                // UUID() makes a unique random ID. "manual-" marks it as not
                // from Radio Browser.
                id: "manual-\(UUID().uuidString)",
                name: name,
                // Keep the address as typed. A playlist link is opened again
                // each time it plays, so it keeps working if the stream moves.
                url: address,
                country: "", tags: "", codec: "", bitrate: 0
            )
            results = [station]
            searchSelection = station.id
            searchMessage = "Found \(name). Play it to try it, or add it to Favorites."
            isSearching = false
            announce(searchMessage)
        }
    }
}
