import Foundation

// MARK: - JSON favorites importer

/// Reads station lists from JSON. Understands:
/// - Crystal Set's own favorites.json
/// - Radio Browser API results (objects with "stationuuid")
/// - Triode favorites exports, and similar lists of objects with "name" and "url"
enum FavoritesImporter {
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

    private struct Wrapper: Decodable {
        let stations: [GenericStation]?
        let favorites: [GenericStation]?
    }

    static func stations(from data: Data) throws -> [Station] {
        let decoder = JSONDecoder()

        if let native = try? decoder.decode([Station].self, from: data), !native.isEmpty {
            return native.filter { !$0.url.isEmpty }
        }
        if let api = try? decoder.decode([APIStation].self, from: data), !api.isEmpty {
            return api.map(\.station).filter { !$0.url.isEmpty }
        }

        let items: [GenericStation]
        if let list = try? decoder.decode([GenericStation].self, from: data) {
            items = list
        } else {
            let wrapper = try decoder.decode(Wrapper.self, from: data)
            items = wrapper.stations ?? wrapper.favorites ?? []
        }

        let stations = items.compactMap(station(from:))
        if stations.isEmpty { throw ImportError.noStations }
        return stations
    }

    private static func station(from item: GenericStation) -> Station? {
        let url = (item.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        let name = (item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        var bitrate = 0
        var codec = ""
        var country = ""
        let parts = (item.description ?? "")
            .components(separatedBy: "•")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var rest = parts[...]
        if let first = rest.first, first.lowercased().hasSuffix("k"),
           let kbps = Int(first.dropLast()) {
            bitrate = kbps
            rest = rest.dropFirst()
        }
        if let next = rest.first, next.count <= 5, next == next.uppercased() {
            codec = next
            rest = rest.dropFirst()
        }
        if let last = rest.last { country = last }

        let guid = item.guid?.trimmingCharacters(in: .whitespaces) ?? ""
        return Station(
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

extension AppModel {
    func importFavorites(from result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importMessage = "The file could not be opened. \(error.localizedDescription)"
        case .success(let fileURL):
            let scoped = fileURL.startAccessingSecurityScopedResource()
            defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
            do {
                let found = try FavoritesImporter.stations(from: Data(contentsOf: fileURL))
                importMessage = merge(found)
            } catch {
                importMessage = "\(fileURL.lastPathComponent) could not be imported. \(error.localizedDescription)"
            }
        }
        showingImportResult = true
    }

    /// Adds stations not already in favorites (matched by ID or stream address)
    /// and returns a summary sentence.
    @discardableResult
    func merge(_ stations: [Station]) -> String {
        var knownIDs = Set(favorites.map(\.id))
        var knownURLs = Set(favorites.map { $0.url.lowercased() })
        var added: [Station] = []
        for station in stations {
            let key = station.url.lowercased()
            guard !knownIDs.contains(station.id), !knownURLs.contains(key) else { continue }
            knownIDs.insert(station.id)
            knownURLs.insert(key)
            added.append(station)
        }
        if !added.isEmpty {
            favorites.append(contentsOf: added)
            favoriteSelection = added.first?.id
            tab = .favorites
        }

        let skipped = stations.count - added.count
        var message = added.count == 1 ? "Imported 1 station." : "Imported \(added.count) stations."
        if skipped > 0 {
            message += skipped == 1
                ? " 1 was already in favorites."
                : " \(skipped) were already in favorites."
        }
        return message
    }
}
