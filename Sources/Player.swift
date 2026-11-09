import AVFoundation
import Combine
import MediaPlayer

// MARK: - Player

/// Plays one internet radio stream at a time and reports what it is doing.
@MainActor
final class Player: ObservableObject {
    enum State: Equatable {
        case stopped
        case connecting
        case playing
        case paused
        case failed(String)

        var description: String {
            switch self {
            case .stopped: return "Stopped"
            case .connecting: return "Connecting…"
            case .playing: return "Playing"
            case .paused: return "Paused"
            case .failed(let reason): return "Could not play: \(reason)"
            }
        }
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var station: Station?
    /// Show or song title sent by the stream (ICY metadata), when available.
    @Published private(set) var streamTitle = ""
    @Published var volume: Double = 0.8 {
        didSet { avPlayer.volume = Float(volume) }
    }

    private let avPlayer = AVPlayer()
    private var statusObserver: AnyCancellable?
    private var itemObserver: AnyCancellable?
    private var metadataDelegate: MetadataDelegate?
    private var loadTask: Task<Void, Never>?

    init() {
        avPlayer.volume = Float(volume)
        statusObserver = avPlayer.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated { self?.timeControlChanged(status) }
            }
        setUpRemoteCommands()
    }

    var isActive: Bool { station != nil && state != .stopped }

    // MARK: Controls

    func play(_ station: Station) {
        loadTask?.cancel()
        avPlayer.pause()
        self.station = station
        streamTitle = ""
        state = .connecting
        announce("Connecting to \(station.name)")
        updateNowPlayingInfo()

        loadTask = Task { [weak self] in
            let url = await StreamResolver.resolve(station.url)
            guard let self, !Task.isCancelled, self.station?.id == station.id else { return }
            guard let url else {
                self.fail("the stream address is not valid.")
                return
            }
            self.start(url)
        }
    }

    func pause() {
        guard state == .playing || state == .connecting else { return }
        avPlayer.pause()
        state = .paused
        announce("Paused")
        updateNowPlayingInfo()
    }

    func resume() {
        guard let station else { return }
        switch state {
        case .paused:
            // A live stream that sat paused is stale; reconnect for the live feed.
            play(station)
        case .stopped, .failed:
            play(station)
        case .playing, .connecting:
            break
        }
    }

    /// Reconnects to the current station, e.g. after the stream drops.
    func reconnect() {
        guard let station else {
            announce("Nothing playing")
            return
        }
        play(station)
    }

    func togglePause() {
        if state == .playing || state == .connecting { pause() } else { resume() }
    }

    func stop() {
        loadTask?.cancel()
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        itemObserver = nil
        metadataDelegate = nil
        if station != nil { announce("Stopped") }
        state = .stopped
        streamTitle = ""
        updateNowPlayingInfo()
    }

    /// Speaks the current station, state, and show title for VoiceOver users.
    func announceStatus() {
        guard let station else {
            announce("Nothing playing")
            return
        }
        var text = "\(station.name). \(state.description)"
        if !streamTitle.isEmpty { text += ". \(streamTitle)" }
        announce(text)
    }

    // MARK: Internals

    private func start(_ url: URL) {
        let item = AVPlayerItem(url: url)

        let delegate = MetadataDelegate { [weak self] title in
            guard let self, self.streamTitle != title else { return }
            self.streamTitle = title
            self.updateNowPlayingInfo()
        }
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(delegate, queue: .main)
        item.add(output)
        metadataDelegate = delegate

        itemObserver = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] status in
                MainActor.assumeIsolated {
                    guard status == .failed else { return }
                    let reason = item?.error?.localizedDescription ?? "the stream could not be opened."
                    self?.fail(reason)
                }
            }

        avPlayer.replaceCurrentItem(with: item)
        avPlayer.play()
    }

    private func fail(_ reason: String) {
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        state = .failed(reason)
        announce(state.description)
        updateNowPlayingInfo()
    }

    private func timeControlChanged(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            if state != .playing {
                let wasConnecting = state == .connecting
                state = .playing
                if wasConnecting, let station { announce("Playing \(station.name)") }
                updateNowPlayingInfo()
            }
        case .waitingToPlayAtSpecifiedRate:
            if state == .playing { state = .connecting }
        case .paused:
            break
        @unknown default:
            break
        }
    }

    // MARK: Media keys and Now Playing

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.togglePause() }
            return .success
        }
        center.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.pause() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.stop() }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        let center = MPNowPlayingInfoCenter.default()
        guard let station, state != .stopped else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: streamTitle.isEmpty ? station.name : streamTitle,
            MPMediaItemPropertyArtist: station.name,
            MPNowPlayingInfoPropertyIsLiveStream: true,
        ]
        if !streamTitle.isEmpty { info[MPMediaItemPropertyAlbumTitle] = station.name }
        center.nowPlayingInfo = info
        center.playbackState = state == .playing ? .playing : .paused
    }
}

// MARK: - Stream metadata

/// Receives ICY "StreamTitle" metadata from Shoutcast and Icecast streams.
private final class MetadataDelegate: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    private let onTitle: @MainActor (String) -> Void

    init(onTitle: @escaping @MainActor (String) -> Void) {
        self.onTitle = onTitle
    }

    func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                        from track: AVPlayerItemTrack?) {
        guard let item = groups.first?.items.first(where: { $0.commonKey == .commonKeyTitle })
                ?? groups.first?.items.first else { return }
        let onTitle = self.onTitle
        Task { @MainActor in
            guard let value = try? await item.load(.stringValue) else { return }
            let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { onTitle(title) }
        }
    }
}

// MARK: - Playlist resolution

/// AVPlayer can't open .pls, .m3u (non-HLS), or .asx playlist files, which many
/// stations publish. This fetches the playlist and returns the first stream in it.
enum StreamResolver {
    static func resolve(_ address: String) async -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }

        let ext = url.pathExtension.lowercased()
        guard ["pls", "m3u", "asx"].contains(ext) else { return url }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("OTRTuner/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              data.count < 200_000,
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return url }

        return firstStream(in: text) ?? url
    }

    static func firstStream(in playlist: String) -> URL? {
        for rawLine in playlist.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            // .pls: File1=http://...
            if let eq = line.firstIndex(of: "="), line.lowercased().hasPrefix("file") {
                line = String(line[line.index(after: eq)...])
            }
            // .asx: <ref href="http://..." />
            if line.lowercased().contains("href=\"") {
                let parts = line.components(separatedBy: "\"")
                if let candidate = parts.first(where: { $0.lowercased().hasPrefix("http") }) {
                    line = candidate
                }
            }
            if line.lowercased().hasPrefix("http"), let url = URL(string: line) {
                return url
            }
        }
        return nil
    }
}
