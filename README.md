# Crystal Set

A small, VoiceOver-friendly macOS app for listening to internet radio. It was built for old time radio (OTR) — mysteries, westerns, comedies and science fiction from radio's golden age — but it plays any internet radio stream. It's named after the crystal set, the simple home-built radio of the early broadcast era.

- Search the free [Radio Browser](https://www.radio-browser.info) station directory by tag or name
- Keep a reorderable list of favorite stations
- Add any stream by its address, including `.pls` and `.m3u` playlist links
- Import favorites from a JSON file, including a [Triode](https://triode.app) favorites export
- Shows the current show title when the stream sends one
- Works with the keyboard's media keys and Control Center's Now Playing

## Accessibility

Crystal Set uses only standard macOS controls: a tab view, tables, buttons, text fields, a picker, and a slider. Nothing is custom-drawn. Every control has a plain text label. Important events are spoken through VoiceOver announcements: connecting, playing, paused, stopped, playback errors, search results, and changes to favorites.

## Requirements

- macOS 13 Ventura or later
- Xcode or the Xcode Command Line Tools (for `swiftc`)

## Build

There is no Xcode project. The build script compiles the sources with `swiftc` and produces an ad hoc signed app bundle. It works from any folder.

To build and install in one step:

```bash
bash ~/Projects/crystal-set/build.sh install
```

This builds the app, quits Crystal Set if it's running, replaces the copy in `/Applications`, and reopens it if it was running.

To build without installing:

```bash
bash ~/Projects/crystal-set/build.sh
```

The app is written to `build/Crystal Set.app` in the project folder.

(Adjust the path if you cloned the project somewhere other than `~/Projects/crystal-set`.)

## Keyboard shortcuts

### In a station table (Favorites or Search results)

| Action | Key |
| --- | --- |
| Play the selected station | Return, or double-click |
| Play, or pause and resume if it's already playing | Space |
| Remove the selected favorite | Command-Delete (Favorites only) |
| Play a station with VoiceOver | VO-Space on its row |

Every row also has a context menu (VO-Shift-M) and VoiceOver actions (VO-Command-Space) with Play and Add to / Remove from Favorites.

### Controls menu

| Action | Shortcut |
| --- | --- |
| Play selected station | Command-Return |
| Pause or resume | Command-P |
| Stop | Command-Period |
| Reconnect to the current stream | Command-R |
| Next / previous station in the current list | Command-Right Arrow / Command-Left Arrow |
| Volume up / down (5% steps) | Command-Up Arrow / Command-Down Arrow |
| Speak what's playing | Command-I |
| Select the playing station in its list | Command-L |

The Command-arrow shortcuts are turned off while you're typing in a text field, so they still move the text cursor there.

### Station and File menus

| Action | Shortcut |
| --- | --- |
| Add or remove selected station from favorites | Command-D |
| Move favorite up / down | Command-Option-Up Arrow / Down Arrow |
| Show Favorites / Search | Command-1 / Command-2 |
| Find stations (focus search field) | Command-F |
| Add station by address | Command-N |
| Import favorites | Command-Shift-I |

## Importing favorites

File > Import Favorites accepts a JSON file in any of these formats:

- **Triode export:** an array of objects with `name`, `url`, `guid` and `description`. The bitrate, codec and country are read from the description.
- **Crystal Set's own favorites file** (see below)
- **Radio Browser API results:** an array of station objects with `stationuuid`

Stations already in your favorites (same ID or same stream address) are skipped.

## Where data is stored

Favorites are saved to `~/Library/Application Support/Crystal Set/favorites.json`. (Crystal Set was first called OTR Tuner. On first launch it copies favorites saved under that name.)

## Source layout

| File | Contents |
| --- | --- |
| `Sources/CrystalSetApp.swift` | App entry point and menu commands |
| `Sources/ContentView.swift` | Window, Favorites and Search tabs, Now Playing bar, Add Station sheet |
| `Sources/StationTable.swift` | AppKit station table: VO-Space, Return, Space and double-click play, Command-Delete, context menu, VoiceOver actions |
| `Sources/Models.swift` | Station model, Radio Browser client, app state, VoiceOver announcements |
| `Sources/Player.swift` | AVPlayer playback, stream title metadata, playlist resolution, media keys |
| `Sources/Importer.swift` | JSON favorites importer |

## License

MIT. See [LICENSE](LICENSE).
