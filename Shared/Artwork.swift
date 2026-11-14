// Artwork.swift
//
// Station logos, for lists, pinned buttons, Now Playing, and the Lock Screen
// and Control Center.
//   - ArtworkStore: downloads a station's logo once, safely, and keeps a
//     small copy on the device so it isn't downloaded again.
//   - StationArtwork: a SwiftUI view showing the logo, or a colored tile with
//     a radio symbol when there isn't a usable one.
//
// Where logos come from: Radio Browser lists a logo address ("favicon") for
// many stations. It's on the station's own website, so fetching it tells that
// website your device's internet address, like visiting it would (see
// PRIVACY.md).
//
// Logos are only for the eye. VoiceOver skips them; the station's name
// already says everything.

import CryptoKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Artwork store

/// Downloads and keeps station logos. An `actor` does one thing at a time, so
/// two views asking for the same logo can't trip over each other.
actor ArtworkStore {
    static let shared = ArtworkStore()

    /// Logos already loaded this session, by address.
    private var memory: [String: CGImage] = [:]
    /// Addresses that failed or had no usable picture, so they aren't retried
    /// over and over in one session.
    private var failed: Set<String> = []

    /// The largest logo file accepted (real ones are a few kilobytes).
    private let sizeLimit = 1_000_000
    /// Logos are shrunk to at most this many pixels across.
    private let maxPixels = 256
    /// Smaller pictures (such as 16-pixel website icons) look blurry blown
    /// up, so a placeholder tile is shown instead.
    private let minPixels = 48

    /// The logo at `address`, or nil if there isn't a usable one.
    func image(at address: String?) async -> CGImage? {
        guard let address, !address.isEmpty, !failed.contains(address) else { return nil }
        if let image = memory[address] { return image }
        if let image = readFromDisk(address) {
            memory[address] = image
            return image
        }
        // Only web addresses, like streams (never a file on the device).
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            failed.insert(address)
            return nil
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("CrystalSet/1.0", forHTTPHeaderField: "User-Agent")
        // StreamResolver.download stops at the size limit, so a huge file
        // can't fill memory.
        guard let data = await StreamResolver.download(request, limit: sizeLimit),
              let image = shrink(data) else {
            failed.insert(address)
            return nil
        }
        memory[address] = image
        writeToDisk(image, address)
        return image
    }

    /// The image already loaded for `address`, without downloading. Used for
    /// the Lock Screen's Now Playing information, which can't wait.
    func cached(_ address: String?) -> CGImage? {
        address.flatMap { memory[$0] }
    }

    /// Decodes the picture and shrinks it. ImageIO reads PNG, JPEG, GIF, ICO
    /// and more, and builds the small version without decoding the whole
    /// picture at full size.
    private func shrink(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              min(width, height) >= minPixels else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: On disk

    /// The app's Caches folder, which the system may empty when space runs
    /// low; logos are simply downloaded again then.
    private var folder: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let folder = caches.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A file name made from the address (its SHA-256 fingerprint), so any
    /// address gives a safe, fixed-length name.
    private func file(for address: String) -> URL {
        let digest = SHA256.hash(data: Data(address.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(digest + ".png")
    }

    private func readFromDisk(_ address: String) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file(for: address) as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func writeToDisk(_ image: CGImage, _ address: String) {
        guard let destination = CGImageDestinationCreateWithURL(
            file(for: address) as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}

// MARK: - The view

/// A station's logo in a rounded square, or a placeholder tile: a radio symbol
/// on a gradient in one of the app icon's colors, picked from the station's
/// name so each station keeps the same color. Hidden from VoiceOver.
struct StationArtwork: View {
    let station: Station?
    var size: CGFloat = 44
    var cornerRadius: CGFloat { size * 0.18 }

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    // Logos with see-through parts sit on white, as they would
                    // on the station's website.
                    .background(Color.white)
            } else {
                Placeholder(name: station?.name ?? "", size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
        // Load (or reload) whenever the station's logo address changes.
        .task(id: station?.favicon) {
            image = await ArtworkStore.shared.image(at: station?.favicon)
        }
    }

    /// The colored tile with a radio symbol.
    private struct Placeholder: View {
        let name: String
        let size: CGFloat

        // The app icon's copper and deep blue, plus three companions.
        private static let palette: [Color] = [
            Color(red: 0.72, green: 0.42, blue: 0.20),   // copper
            Color(red: 0.12, green: 0.24, blue: 0.52),   // deep blue
            Color(red: 0.10, green: 0.42, blue: 0.46),   // teal
            Color(red: 0.42, green: 0.20, blue: 0.40),   // plum
            Color(red: 0.20, green: 0.40, blue: 0.26),   // forest green
        ]

        /// The same color for the same name every time. (Swift's own hash
        /// changes each time the app runs, so this is a simple sum instead.)
        private var color: Color {
            let total = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
            return Self.palette[total % Self.palette.count]
        }

        var body: some View {
            ZStack {
                LinearGradient(colors: [color, color.opacity(0.7)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "radio")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }
}
