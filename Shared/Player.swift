// Player.swift
//
// Everything to do with sound:
//   - Player: plays one stream at a time, tracks whether it's connecting,
//     playing, paused, stopped or failed, and runs the sleep timer.
//   - MetadataDelegate: picks up the show title some streams send.
//   - StreamResolver: opens playlist links (.pls, .m3u, .asx) to find the
//     actual stream inside them.
//
// The Player knows nothing about windows or buttons. The screens watch it
// and call its functions, such as play(_:), pause() and stop(). Both the Mac
// and iPhone versions use it; the few differences are marked `#if os(...)`.

// AVFoundation is Apple's audio and video toolkit; it provides AVPlayer,
// which does the actual streaming. Combine lets code watch values change.
// MediaPlayer connects to the keyboard's media keys and to Now Playing.
import AVFoundation
import Combine
import MediaPlayer

// MARK: - Player

/// Plays one internet radio stream at a time and reports what it is doing.
@MainActor
final class Player: ObservableObject {
    /// What the player is doing right now.
    ///
    /// `failed` carries a reason with it, such as "the stream could not be opened."
    enum State: Equatable {
        case stopped
        case connecting
        case playing
        case paused
        case failed(String)

        /// The words shown and spoken for each state.
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

    // `private(set)` means other files can read these but only the Player can change them.
    @Published private(set) var state: State = .stopped
    // The station playing (or last played), or nil.
    @Published private(set) var station: Station?
    /// Show or song title sent by the stream (ICY metadata), when available.
    @Published private(set) var streamTitle = ""
    // The volume setting, from 0 (silent) to 1 (full). 0.8 is 80%.
    // `didSet` passes every change straight on to the audio player.
    // On iPhone it starts at full, since the phone's volume buttons set the level.
    #if os(iOS)
    @Published var volume: Double = 1.0 {
        didSet { avPlayer.volume = Float(volume) }
    }
    #else
    @Published var volume: Double = 0.8 {
        didSet { avPlayer.volume = Float(volume) }
    }
    #endif

    // Apple's player object, which does the streaming.
    private let avPlayer = AVPlayer()
    // These keep "watchers" alive; when one is set to nil, its watching stops.
    private var statusObserver: AnyCancellable?
    private var itemObserver: AnyCancellable?
    private var metadataDelegate: MetadataDelegate?
    // The background job that opens a stream, so it can be cancelled.
    private var loadTask: Task<Void, Never>?

    init() {
        #if os(iOS)
        // Tell iOS this app plays audio, so it keeps playing when the screen
        // locks or you switch apps, and isn't silenced by the ring/silent switch.
        // (Info.plist also lists "audio" under background modes.)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        #endif
        avPlayer.volume = Float(volume)
        // Watch AVPlayer's own status (playing, waiting for data, paused) and
        // call timeControlChanged(_:) each time it changes.
        // `[weak self]` stops the watcher from keeping the Player alive forever.
        statusObserver = avPlayer.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated { self?.timeControlChanged(status) }
            }
        setUpRemoteCommands()
    }

    /// True when a station is connecting, playing, paused or failed (anything but stopped).
    var isActive: Bool { station != nil && state != .stopped }

    // MARK: Controls

    /// Starts playing a station.
    ///
    /// The stream opens in the background, so this returns straight away. The
    /// state goes to `.connecting`, then to `.playing` once sound arrives
    /// (see timeControlChanged), or to `.failed` if the stream can't be opened.
    func play(_ station: Station) {
        // Cancel any stream still being opened, and silence the current one.
        loadTask?.cancel()
        avPlayer.pause()
        self.station = station
        streamTitle = ""
        state = .connecting
        announce("Connecting to \(station.name)")
        updateNowPlayingInfo()

        loadTask = Task { [weak self] in
            // Turn a playlist link into the real stream address (see StreamResolver).
            let url = await StreamResolver.resolve(station.url)
            // While that ran, the person may have picked another station or
            // stopped; if so, give up on this one.
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
        // The sleep timer waits while the stream is paused (see startSleepTimer).
        announce(sleepTimerMinutes > 0 ? "Paused. Sleep timer paused" : "Paused")
        updateNowPlayingInfo()
    }

    /// Resumes a paused station, or replays a stopped or failed one.
    func resume() {
        guard let station else { return }
        switch state {
        case .paused:
            // A live stream that sat paused is stale; reconnect for the live feed.
            play(station)
        case .stopped, .failed:
            play(station)
        case .playing, .connecting:
            // Already going; nothing to do.
            break
        }
    }

    /// Reconnects to the current station, e.g. after the stream drops.
    /// Command-R.
    func reconnect() {
        guard let station else {
            announce("Nothing playing")
            return
        }
        play(station)
    }

    // Command-P, the Pause/Resume button, and the keyboard's play/pause key.
    func togglePause() {
        if state == .playing || state == .connecting { pause() } else { resume() }
    }

    /// Stops playback. Also turns off the sleep timer, since there's nothing left to stop.
    func stop() {
        let hadTimer = sleepTimerMinutes > 0
        cancelSleepTimer()
        let wasPlaying = station != nil
        stopPlayback()
        if wasPlaying { announce(hadTimer ? "Stopped. Sleep timer off" : "Stopped") }
    }

    // The part of stopping shared by stop() and the sleep timer. It speaks nothing.
    private func stopPlayback() {
        loadTask?.cancel()
        avPlayer.pause()
        // Let go of the stream entirely, so it stops downloading.
        avPlayer.replaceCurrentItem(with: nil)
        itemObserver = nil
        metadataDelegate = nil
        state = .stopped
        streamTitle = ""
        updateNowPlayingInfo()
    }

    /// Picks up a new name for the station playing, after it's renamed in Favorites.
    func stationRenamed(_ renamed: Station) {
        guard station?.id == renamed.id else { return }
        station = renamed
        updateNowPlayingInfo()
    }

    /// Speaks the current station, state, show title, and sleep timer for VoiceOver users.
    /// Command-I.
    func announceStatus() {
        var text: String
        if let station {
            text = "\(station.name). \(state.description)"
            if !streamTitle.isEmpty { text += ". \(streamTitle)" }
        } else {
            text = "Nothing playing"
        }
        if let sleepTimerDescription { text += ". \(sleepTimerDescription)" }
        announce(text)
    }

    // MARK: Sleep timer

    /// Sleep timer lengths offered in menus, in minutes.
    /// Change this list to offer different choices; the menus update to match.
    static let sleepTimerChoices = [15, 30, 45, 60, 90]

    /// Length of the running sleep timer in minutes, or 0 when it's off.
    @Published private(set) var sleepTimerMinutes = 0
    /// Whole minutes left, rounded up. Changes at most once a minute, so
    /// VoiceOver isn't interrupted by a ticking countdown. Nil when off.
    @Published private(set) var sleepMinutesLeft: Int?
    /// The sound fades out over this many seconds before playback stops.
    var sleepFadeDuration: TimeInterval = 30
    /// The volume actually sent to the speakers (lower than `volume` during the fade).
    var outputVolume: Float { avPlayer.volume }

    // The background job that counts down, so it can be cancelled.
    private var sleepTask: Task<Void, Never>?

    /// "Sleep timer: 23 minutes left", "Sleep timer paused: 23 minutes left"
    /// while the stream is paused, or nil when the timer is off.
    var sleepTimerDescription: String? {
        guard let left = sleepMinutesLeft else { return nil }
        let label = state == .paused ? "Sleep timer paused" : "Sleep timer"
        return left == 1 ? "\(label): 1 minute left" : "\(label): \(left) minutes left"
    }

    /// Starts a sleep timer for the given minutes; 0 turns it off.
    func setSleepTimer(minutes: Int) {
        cancelSleepTimer()
        guard minutes > 0 else {
            announce("Sleep timer off")
            return
        }
        startSleepTimer(seconds: TimeInterval(minutes * 60), minutes: minutes)
        announce("Sleep timer set for \(minutes) minutes")
    }

    /// Steps through Off, 15, 30, 45, 60, 90 minutes, then back to Off.
    /// Command-T.
    func cycleSleepTimer() {
        // 0 stands for Off. `%` wraps the position back to 0 after the last choice.
        let all = [0] + Self.sleepTimerChoices
        let index = all.firstIndex(of: sleepTimerMinutes) ?? 0
        setSleepTimer(minutes: all[(index + 1) % all.count])
    }

    /// Starts a timer of any length in seconds. `minutes` is the menu choice it stands for.
    /// (Taking seconds lets a quick test use a timer of a few seconds.)
    func startSleepTimer(seconds: TimeInterval, minutes: Int) {
        cancelSleepTimer()
        sleepTimerMinutes = minutes
        // Seconds still to run. This counts down only while the stream isn't
        // paused, so pausing for ten minutes doesn't use up ten minutes of the
        // timer. (A fixed end time on the clock couldn't wait like that.)
        updateSleepMinutesLeft(seconds)

        // Check the clock four times a second rather than sleeping for the whole
        // length, so the timer stays right across Mac sleep and the fade is smooth.
        // Each check takes off the real time since the last one, unless paused.
        sleepTask = Task { [weak self] in
            var left = seconds
            var lastCheck = Date()
            while !Task.isCancelled {
                guard let self else { return }
                let now = Date()
                if self.state != .paused {
                    left -= now.timeIntervalSince(lastCheck)
                }
                lastCheck = now
                if left <= 0 {
                    self.finishSleepTimer()
                    return
                }
                self.updateSleepMinutesLeft(left)
                // In the last `sleepFadeDuration` seconds, lower the output in
                // step with the time left: half the time left, half the volume.
                // The `volume` setting itself is untouched.
                if left < self.sleepFadeDuration {
                    self.avPlayer.volume = Float(self.volume * left / self.sleepFadeDuration)
                }
                // Wait a quarter of a second (250 million nanoseconds).
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    // Updates the minutes-left value, but only when the whole number changes.
    private func updateSleepMinutesLeft(_ secondsLeft: TimeInterval) {
        let minutes = max(1, Int((secondsLeft / 60).rounded(.up)))
        if sleepMinutesLeft != minutes { sleepMinutesLeft = minutes }
    }

    // Turns the timer off and puts the output volume back to the setting.
    private func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimerMinutes = 0
        sleepMinutesLeft = nil
        avPlayer.volume = Float(volume)
    }

    // Runs when the timer reaches zero.
    private func finishSleepTimer() {
        sleepTask = nil
        sleepTimerMinutes = 0
        sleepMinutesLeft = nil
        if station != nil, state != .stopped {
            stopPlayback()
            announce("Sleep timer ended. Stopped")
        } else {
            announce("Sleep timer ended")
        }
        // Back to normal volume, ready for the next time something plays.
        avPlayer.volume = Float(volume)
    }

    // MARK: Internals

    /// Hands a real stream address to AVPlayer and starts it.
    private func start(_ url: URL) {
        #if os(iOS)
        // Claim the iPhone's audio, pausing other apps' audio.
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let item = AVPlayerItem(url: url)

        // Listen for show titles sent by the stream.
        let delegate = MetadataDelegate { [weak self] title in
            guard let self, self.streamTitle != title else { return }
            self.streamTitle = title
            self.updateNowPlayingInfo()
        }
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(delegate, queue: .main)
        item.add(output)
        metadataDelegate = delegate

        // Watch for the stream failing to open, and report why.
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

    // Stops and reports a problem, such as a stream that won't open.
    private func fail(_ reason: String) {
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        state = .failed(reason)
        announce(state.description)
        updateNowPlayingInfo()
    }

    // Called whenever AVPlayer's own status changes.
    private func timeControlChanged(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            // Sound is coming out.
            if state != .playing {
                let wasConnecting = state == .connecting
                state = .playing
                // Say "Playing" only when a new connection succeeds, not after
                // every brief pause to wait for more data.
                if wasConnecting, let station { announce("Playing \(station.name)") }
                updateNowPlayingInfo()
            }
        case .waitingToPlayAtSpecifiedRate:
            // The stream ran short of data and is waiting for more (buffering).
            if state == .playing { state = .connecting }
        case .paused:
            // Something else paused the audio, such as a phone call, Siri,
            // another app starting to play, or headphones being unplugged.
            // (Crystal Set's own pause() changes `state` first, so this
            // doesn't affect it.)
            if state == .playing || state == .connecting {
                state = .paused
                updateNowPlayingInfo()
            }
        // Covers any status a future macOS or iOS might add.
        @unknown default:
            break
        }
    }

    // MARK: Media keys and Now Playing

    // Lets the keyboard's media keys, headphones, and Control Center's Now
    // Playing control this player. Each "target" is the code to run for one
    // command; it hops to the main thread, since that's where the Player lives.
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

    // Tells macOS what's playing, for Control Center's Now Playing.
    private func updateNowPlayingInfo() {
        let center = MPNowPlayingInfoCenter.default()
        guard let station, state != .stopped else {
            center.nowPlayingInfo = nil
            #if os(macOS)
            // Only the Mac needs to be told this; the iPhone works it out itself.
            center.playbackState = .stopped
            #endif
            return
        }
        // Show the show title when there is one, with the station as the "artist".
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: streamTitle.isEmpty ? station.name : streamTitle,
            MPMediaItemPropertyArtist: station.name,
            MPNowPlayingInfoPropertyIsLiveStream: true,
        ]
        if !streamTitle.isEmpty { info[MPMediaItemPropertyAlbumTitle] = station.name }
        center.nowPlayingInfo = info
        #if os(macOS)
        center.playbackState = state == .playing ? .playing : .paused
        #endif
    }
}

// MARK: - Stream metadata

/// Receives ICY "StreamTitle" metadata from Shoutcast and Icecast streams.
///
/// Many internet radio servers send the current show or song title alongside
/// the audio. AVPlayer passes it to a "delegate" object like this one; it
/// hands each title to the `onTitle` code it was given.
private final class MetadataDelegate: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    // The code to run with each new title (a "closure": code stored like a value).
    private let onTitle: @MainActor (String) -> Void

    init(onTitle: @escaping @MainActor (String) -> Void) {
        self.onTitle = onTitle
    }

    // AVPlayer calls this whenever the stream sends new metadata.
    func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                        from track: AVPlayerItemTrack?) {
        // Prefer an item marked as the title; otherwise take the first item.
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
///
/// A playlist file is a short text file listing stream addresses, for example:
///   [playlist]
///   File1=http://example.com:8000/stream
enum StreamResolver {
    /// Returns the address to play: the stream inside a playlist, or the
    /// address itself if it isn't a playlist. Nil if the address isn't valid.
    static func resolve(_ address: String) async -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only web addresses (http or https) can be played.
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }

        // Not a playlist? Play the address as it is.
        let ext = url.pathExtension.lowercased()
        guard ["pls", "m3u", "asx"].contains(ext) else { return url }

        // Download the playlist (giving up after 15 seconds, or if it's
        // suspiciously large) and read it as text.
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("CrystalSet/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              data.count < 200_000,
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return url }

        // If no stream is found inside, try the original address anyway.
        return firstStream(in: text) ?? url
    }

    /// Asks a stream for its station name, or returns nil if it doesn't say.
    ///
    /// Shoutcast and Icecast servers send the name in an "icy-name" header
    /// at the start of the stream. This reads just the headers, then hangs
    /// up, so no audio is downloaded.
    static func stationName(at url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("CrystalSet/1.0", forHTTPHeaderField: "User-Agent")
        // Asks the server for its "ICY" station details.
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        // `bytes(for:)` returns as soon as the headers arrive, before the audio.
        guard let (bytes, response) = try? await URLSession.shared.bytes(for: request) else { return nil }
        bytes.task.cancel()
        guard let http = response as? HTTPURLResponse,
              let name = http.value(forHTTPHeaderField: "icy-name")?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              // Some servers send a placeholder instead of a real name.
              !name.isEmpty, name.lowercased() != "unspecified name", name.lowercased() != "no name"
        else { return nil }
        return name
    }

    /// Finds the first web address in a playlist's text, reading it line by line.
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
            // .m3u lines are plain addresses, so they need no special handling.
            if line.lowercased().hasPrefix("http"), let url = URL(string: line) {
                return url
            }
        }
        return nil
    }
}
