import Foundation
import AppKit

// MARK: - Station

struct Station: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var url: String
    var country: String
    var tags: String
    var codec: String
    var bitrate: Int

    /// Radio Browser stations use its station UUID as their ID. Stations added
    /// by hand or imported from a file get a prefixed ID instead.
    var isFromRadioBrowser: Bool { !(id.hasPrefix("manual-") || id.hasPrefix("import-")) }

    var formatDescription: String {
        var parts: [String] = []
        if !codec.isEmpty { parts.append(codec) }
        if bitrate > 0 { parts.append("\(bitrate) kbps") }
        return parts.joined(separator: ", ")
    }
}

/// Shape of a station as returned by the Radio Browser API.
struct APIStation: Decodable {
    let stationuuid: String
    let name: String?
    let url: String?
    let url_resolved: String?
    let country: String?
    let tags: String?
    let codec: String?
    let bitrate: Int?

    var station: Station {
        let resolved = url_resolved ?? ""
        return Station(
            id: stationuuid,
            name: (name ?? "Unnamed station").trimmingCharacters(in: .whitespacesAndNewlines),
            url: resolved.isEmpty ? (url ?? "") : resolved,
            country: country ?? "",
            tags: (tags ?? "").replacingOccurrences(of: ",", with: ", "),
            codec: codec ?? "",
            bitrate: bitrate ?? 0
        )
    }
}

enum SearchField: String, CaseIterable, Identifiable {
    case tag = "Tag"
    case name = "Name"
    var id: String { rawValue }
}

// MARK: - Radio Browser client

actor RadioBrowserClient {
    private struct Server: Decodable { let name: String }

    private var baseURL: URL?
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "OTRTuner/1.0"]
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    /// Radio Browser asks clients to pick one of its mirror servers.
    private func server() async -> URL {
        if let baseURL { return baseURL }
        var chosen = URL(string: "https://de1.api.radio-browser.info")!
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

    func search(_ text: String, by field: SearchField) async throws -> [Station] {
        let base = await server()
        var components = URLComponents(url: base.appendingPathComponent("json/stations/search"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: field == .tag ? "tag" : "name", value: text),
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
            URLQueryItem(name: "limit", value: "200"),
        ]
        let (data, response) = try await session.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            baseURL = nil  // try a different mirror next time
            throw URLError(.badServerResponse)
        }
        var seen = Set<String>()
        return try JSONDecoder().decode([APIStation].self, from: data)
            .map(\.station)
            .filter { !$0.url.isEmpty && seen.insert($0.id).inserted }
    }

    /// Tells Radio Browser a station was played (helps its popularity ranking).
    func countClick(_ stationID: String) async {
        let base = await server()
        _ = try? await session.data(from: base.appendingPathComponent("json/url/\(stationID)"))
    }
}

// MARK: - VoiceOver announcements

@MainActor
func announce(_ text: String) {
    NSAccessibility.post(
        element: NSApp as Any,
        notification: .announcementRequested,
        userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ]
    )
}

// MARK: - App model

@MainActor
final class AppModel: ObservableObject {
    enum Tab: Hashable { case favorites, search }

    @Published var tab: Tab = .favorites
    @Published var favorites: [Station] = [] { didSet { saveFavorites() } }
    @Published var favoriteSelection: Station.ID?
    @Published var results: [Station] = []
    @Published var searchSelection: Station.ID?
    @Published var query = "old time radio"
    @Published var field: SearchField = .tag
    @Published var isSearching = false
    @Published var searchMessage = ""
    @Published var showingAddSheet = false
    @Published var showingImporter = false
    @Published var showingImportResult = false
    @Published var focusSearchField = false
    /// True while a text field has focus, so arrow-key menu shortcuts
    /// (Command-Left/Right/Up/Down) go to the text field instead.
    @Published var isEditingText = false
    var importMessage = ""

    let player = Player()
    private let client = RadioBrowserClient()

    private var favoritesFile: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OTR Tuner", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("favorites.json")
    }

    init() {
        if let data = try? Data(contentsOf: favoritesFile),
           let saved = try? JSONDecoder().decode([Station].self, from: data) {
            favorites = saved
            favoriteSelection = saved.first?.id
        }
    }

    private func saveFavorites() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(favorites) {
            try? data.write(to: favoritesFile, options: .atomic)
        }
    }

    // Selection

    var selectedStation: Station? {
        switch tab {
        case .favorites:
            return favorites.first { $0.id == favoriteSelection }
        case .search:
            return results.first { $0.id == searchSelection }
        }
    }

    func isFavorite(_ station: Station) -> Bool {
        favorites.contains { $0.id == station.id }
    }

    // Playback

    func play(_ station: Station) {
        player.play(station)
        if station.isFromRadioBrowser {
            Task { await client.countClick(station.id) }
        }
    }

    func playSelected() {
        if let station = selectedStation { play(station) }
    }

    /// Plays the station, or pauses and resumes it if it's the one already playing.
    func playOrPause(_ station: Station) {
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

    private var currentSelection: Station.ID? {
        get { tab == .favorites ? favoriteSelection : searchSelection }
        set {
            if tab == .favorites { favoriteSelection = newValue } else { searchSelection = newValue }
        }
    }

    /// Plays the next (+1) or previous (-1) station in the current tab's list.
    func playAdjacent(_ offset: Int) {
        let list = currentList
        guard !list.isEmpty else {
            announce(tab == .favorites ? "No favorites" : "No search results")
            return
        }
        let anchor = currentSelection ?? player.station?.id
        let index = anchor.flatMap { id in list.firstIndex { $0.id == id } }
        let next = index.map { $0 + offset } ?? (offset > 0 ? 0 : list.count - 1)
        guard list.indices.contains(next) else {
            announce(offset > 0 ? "Last station" : "First station")
            return
        }
        currentSelection = list[next].id
        play(list[next])
    }

    /// Selects the playing station in Favorites (or Search results) and shows that tab.
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

    func changeVolume(by step: Double) {
        // Step in tenths, rounded so repeated presses land on 0%, 10%, … 100%.
        let newVolume = min(1, max(0, ((player.volume + step) * 10).rounded() / 10))
        player.volume = newVolume
        announce("Volume \(Int((newVolume * 100).rounded())) percent")
    }

    // Favorites

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
        if favoriteSelection == station.id {
            favoriteSelection = favorites.isEmpty ? nil : favorites[min(index, favorites.count - 1)].id
        }
        announce("Removed \(station.name) from favorites")
    }

    func toggleFavoriteForSelection() {
        guard let station = selectedStation else { return }
        if isFavorite(station) { removeFromFavorites(station) } else { addToFavorites(station) }
    }

    func moveSelectedFavorite(by offset: Int) {
        guard let id = favoriteSelection,
              let i = favorites.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard favorites.indices.contains(j) else { return }
        favorites.swapAt(i, j)
        announce("Position \(j + 1) of \(favorites.count)")
    }

    func addManual(name: String, url: String) {
        let station = Station(
            id: "manual-\(UUID().uuidString)",
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            country: "", tags: "", codec: "", bitrate: 0
        )
        favorites.append(station)
        favoriteSelection = station.id
        tab = .favorites
        announce("Added \(station.name) to favorites")
    }

    // Search

    func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSearching else { return }
        isSearching = true
        searchMessage = "Searching…"
        Task {
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
}
