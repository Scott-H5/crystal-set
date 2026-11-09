# OTR Tuner

A small, VoiceOver-friendly macOS app for listening to old time radio (OTR) internet streams.

- Search the free [Radio Browser](https://www.radio-browser.info) station directory by tag or name
- Keep a reorderable list of favorite stations
- Add any stream by its address, including `.pls` and `.m3u` playlist links
- Import favorites from a JSON file, including a [Triode](https://triode.app) favorites export
- Shows the current show title when the stream sends one
- Works with the keyboard's media keys and Control Center's Now Playing

## Accessibility

OTR Tuner uses only standard SwiftUI controls: a tab view, tables, buttons, text fields, a picker, and a slider. Nothing is custom-drawn. Every control has a plain text label. Important events are spoken through VoiceOver announcements: connecting, playing, paused, stopped, playback errors, search results, and changes to favorites.

## Requirements

- macOS 13 Ventura or later
- Xcode or the Xcode Command Line Tools (for `swiftc`)

## Build

There is no Xcode project. The build script compiles the sources with `swiftc` and produces an ad hoc signed app bundle:

```bash
bash build.sh
```

The app is written to `build/OTR Tuner.app`. To install it:

```bash
cp -R "build/OTR Tuner.app" /Applications/
```

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Play selected station | Command-Return, or Return / double-click in a table |
| Pause or resume | Command-P |
| Stop | Command-Period |
| Speak what's playing | Command-I |
| Add or remove selected station from favorites | Command-D |
| Move favorite up / down | Command-Option-Up Arrow / Down Arrow |
| Show Favorites / Search | Command-1 / Command-2 |
| Find stations (focus search field) | Command-F |
| Add station by address | Command-N |
| Import favorites | Command-Shift-I |

Every table row also has a context menu (VoiceOver: VO-Shift-M) with Play and Add to / Remove from Favorites.

## Importing favorites

File > Import Favorites accepts a JSON file in any of these formats:

- **Triode export:** an array of objects with `name`, `url`, `guid` and `description`. The bitrate, codec and country are read from the description.
- **OTR Tuner's own favorites file** (see below)
- **Radio Browser API results:** an array of station objects with `stationuuid`

Stations already in your favorites (same ID or same stream address) are skipped.

## Where data is stored

Favorites are saved to `~/Library/Application Support/OTR Tuner/favorites.json`.

## Source layout

| File | Contents |
| --- | --- |
| `Sources/OTRTunerApp.swift` | App entry point and menu commands |
| `Sources/ContentView.swift` | Window, Favorites and Search tabs, Now Playing bar, Add Station sheet |
| `Sources/Models.swift` | Station model, Radio Browser client, app state, VoiceOver announcements |
| `Sources/Player.swift` | AVPlayer playback, stream title metadata, playlist resolution, media keys |
| `Sources/Importer.swift` | JSON favorites importer |

## License

MIT. See [LICENSE](LICENSE).
