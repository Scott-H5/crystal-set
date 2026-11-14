// ImportExport.swift
//
// Reading and writing favorites as JSON files.
//   - FavoritesImporter: turns a JSON file into a list of Stations. It
//     understands three formats: Crystal Set's own, Radio Browser's, and
//     Triode's favorites export.
//   - importFavorites / merge: add imported stations to Favorites, skipping
//     any you already have, and report what happened.
//   - FavoritesDocument / exportFinished: save Favorites to a JSON file
//     (File > Export Favorites).
//
// JSON is a plain-text format for structured data. A favorites file is a
// list in square brackets, with one station in curly braces per entry, such as
//   [ { "name" : "Gunsmoke", "url" : "https://...", ... }, ... ]

import Foundation
import SwiftUI
// UniformTypeIdentifiers describes file types, such as ".json".
import UniformTypeIdentifiers

// MARK: - JSON favorites importer

/// Reads station lists from JSON. Understands:
/// - Crystal Set's own favorites.json
/// - Radio Browser API results (objects with "stationuuid")
/// - Triode favorites exports, and similar lists of objects with "name" and "url"
///
/// This enum has no cases; it's used only as a named container for the
/// importer's functions, so they're called as `FavoritesImporter.stations(...)`.
enum FavoritesImporter {
    /// The error shown when a file has no usable stations in it.
    enum ImportError: LocalizedError {
        case noStations
        var errorDescription: String? { "No stations with a stream address were found in the file." }
    }

    /// Triode export entry. Its "description" looks like
    /// "48k • MP3 • London, England • The United Kingdom…".
    private struct GenericStation: Decodable {
        let name: String?
        let url: String?
        let guid: String?
        let description: String?
    }

    /// Some apps wrap the list, as in { "stations": [ ... ] }.
    private struct Wrapper: Decodable {
        let stations: [GenericStation]?
        let favorites: [GenericStation]?
    }

    /// Works out which format `data` is in and returns its stations.
    /// Each format is tried in turn; the first one that fits wins.
    static func stations(from data: Data) throws -> [Station] {
        let decoder = JSONDecoder()

        // 1. Crystal Set's own format (what Export writes).
        if let native = try? decoder.decode([Station].self, from: data), !native.isEmpty {
            return native.filter { !$0.url.isEmpty }
        }
        // 2. Radio Browser's format.
        if let api = try? decoder.decode([APIStation].self, from: data), !api.isEmpty {
            return api.map(\.station).filter { !$0.url.isEmpty }
        }

        // 3. Triode, or any list of objects with a name and url,
        //    either on its own or wrapped as described above.
        let items: [GenericStation]
        if let list = try? decoder.decode([GenericStation].self, from: data) {
            items = list
        } else {
            let wrapper = try decoder.decode(Wrapper.self, from: data)
            items = wrapper.stations ?? wrapper.favorites ?? []
        }

        // `compactMap` converts each item and drops the ones that come back nil.
        let stations = items.compactMap(station(from:))
        if stations.isEmpty { throw ImportError.noStations }
        return stations
    }

    /// Converts one Triode-style entry into a Station, or nil if it has no stream address.
    private static func station(from item: GenericStation) -> Station? {
        let url = (item.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        // TextLimit (Player.swift) keeps a name from a file to a sensible length.
        let name = TextLimit.trimmed(item.name ?? "")

        // Pull bitrate, codec and country out of a description such as
        // "48k • MP3 • London, England • The United Kingdom".
        var bitrate = 0
        var codec = ""
        var country = ""
        // Split at each "•" and tidy the pieces: ["48k", "MP3", "London, England", ...]
        let parts = (item.description ?? "")
            .components(separatedBy: "•")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // `rest` is the pieces not used yet. `[...]` makes a view of the whole list.
        var rest = parts[...]
        // A first piece like "48k" is the bitrate.
        if let first = rest.first, first.lowercased().hasSuffix("k"),
           let kbps = Int(first.dropLast()) {
            bitrate = kbps
            rest = rest.dropFirst()
        }
        // A short all-capitals piece like "MP3" or "AAC" is the codec.
        if let next = rest.first, next.count <= 5, next == next.uppercased() {
            codec = next
            rest = rest.dropFirst()
        }
        // The last piece is the country.
        if let last = rest.last { country = last }

        let guid = item.guid?.trimmingCharacters(in: .whitespaces) ?? ""
        return Station(
            // Reuse Triode's ID when there is one, so importing twice is detected.
            id: "import-" + (guid.isEmpty ? UUID().uuidString : guid),
            name: name.isEmpty ? url : name,
            url: url,
            country: country,
            tags: "",
            codec: codec,
            bitrate: bitrate
        )
    }
}

// MARK: - Importing into favorites

// An `extension` adds more functions to a type defined elsewhere, here
// AppModel from Models.swift. It keeps import code together in this file.
extension AppModel {
    /// Called with the file chosen in the Import panel (see ContentView.swift).
    ///
    /// `Result` holds either success (the file's address) or failure (an error).
    func importFavorites(from result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            resultTitle = "Import Favorites"
            importMessage = "The file could not be opened. \(error.localizedDescription)"
        case .success(let fileURL):
            resultTitle = "Import Favorites"
            // macOS requires asking for permission to read a file the person
            // picked; `defer` gives that permission back when this block ends.
            let scoped = fileURL.startAccessingSecurityScopedResource()
            defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
            do {
                let found = try FavoritesImporter.stations(from: Data(contentsOf: fileURL))
                importMessage = merge(found)
            } catch {
                importMessage = "\(fileURL.lastPathComponent) could not be imported. \(error.localizedDescription)"
            }
        }
        // Show the alert with the message.
        showingImportResult = true
    }

    /// Adds stations not already in favorites (matched by ID or stream address)
    /// and returns a summary sentence.
    ///
    /// `@discardableResult` means callers may ignore the returned sentence.
    @discardableResult
    func merge(_ stations: [Station]) -> String {
        // Sets of what's already in Favorites, for quick "have we got it?" checks.
        // Addresses are compared in lowercase so "HTTP://X" matches "http://x".
        var knownIDs = Set(favorites.map(\.id))
        var knownURLs = Set(favorites.map { $0.url.lowercased() })
        var added: [Station] = []
        for station in stations {
            let key = station.url.lowercased()
            // Already have it? `continue` skips to the next station.
            guard !knownIDs.contains(station.id), !knownURLs.contains(key) else { continue }
            knownIDs.insert(station.id)
            knownURLs.insert(key)
            // Imported stations arrive unpinned. A file exported from another
            // device may have its own pins, which could take this list past
            // the five-pin limit.
            var station = station
            station.pinned = nil
            added.append(station)
        }
        // Add them all at once, so favorites are saved once rather than per station.
        if !added.isEmpty {
            favorites.append(contentsOf: added)
            favoriteSelection = added.first?.id
            tab = .favorites
        }

        // Build a sentence like "Imported 3 stations. 9 were already in favorites."
        let skipped = stations.count - added.count
        var message = added.count == 1 ? "Imported 1 station." : "Imported \(added.count) stations."
        if skipped > 0 {
            // `condition ? a : b` means "if condition, a, otherwise b".
            message += skipped == 1
                ? " 1 was already in favorites."
                : " \(skipped) were already in favorites."
        }
        return message
    }
}

// MARK: - Exporting favorites

/// Favorites saved as JSON in Crystal Set's own format, which keeps every
/// field and can be imported again.
///
/// `FileDocument` is SwiftUI's way to describe a file the Save panel can write.
struct FavoritesDocument: FileDocument {
    // The file types this document can be read from.
    static var readableContentTypes: [UTType] { [.json] }

    var stations: [Station]

    init(stations: [Station]) {
        self.stations = stations
    }

    // Required by FileDocument: how to read this kind of file.
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        stations = try FavoritesImporter.stations(from: data)
    }

    // Required by FileDocument: how to write it. Called by the Save panel.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try Self.encode(stations))
    }

    /// Converts stations to JSON text, indented for easy reading, with
    /// web addresses written plainly (no "\/" in place of "/").
    static func encode(_ stations: [Station]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(stations)
    }
}

extension AppModel {
    /// The current favorites, ready for the Save panel.
    var favoritesDocument: FavoritesDocument { FavoritesDocument(stations: favorites) }

    /// Called when the Save panel closes; reports the result in an alert.
    func exportFinished(_ result: Result<URL, Error>) {
        resultTitle = "Export Favorites"
        switch result {
        case .success(let url):
            let count = favorites.count == 1 ? "1 station" : "\(favorites.count) stations"
            importMessage = "Exported \(count) to \(url.lastPathComponent)."
        case .failure(let error):
            // Pressing Cancel counts as an "error"; show nothing for it.
            if (error as? CocoaError)?.code == .userCancelled { return }
            importMessage = "The favorites could not be exported. \(error.localizedDescription)"
        }
        showingImportResult = true
    }
}
