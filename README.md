# Crystal Set

A small, VoiceOver-friendly internet radio app for the Mac and iPhone. It was built for old time radio (OTR) — mysteries, westerns, comedies and science fiction from radio's golden age — but it plays any internet radio stream. It's named after the crystal set, the simple home-built radio of the early broadcast era.

- Search the free [Radio Browser](https://www.radio-browser.info) station directory by tag or name
- Keep a reorderable list of favorite stations, and rename them
- Add any stream by pasting its address into the Search field, including `.pls` and `.m3u` playlist links
- Import favorites from a JSON file, including a [Triode](https://triode.app) favorites export, and export them as JSON
- Shows the current show title when the stream sends one
- Sleep timer (15 to 90 minutes) that fades the sound out over the last 30 seconds
- Works with the keyboard's media keys, the Lock Screen, and Control Center's Now Playing

The Mac and iPhone versions share their stations, search, playback, sleep timer, and import and export code; only the screens differ. Favorites don't sync between them yet, but you can export them on one and import them on the other.

## Accessibility

Crystal Set uses only standard controls: tabs, tables and lists, buttons, text fields, pickers, and a slider. Nothing is custom-drawn. Every control has a plain text label. Important events are spoken through VoiceOver announcements: connecting, playing, paused, stopped, playback errors, search results, sleep timer changes, and changes to favorites.

On iPhone, with VoiceOver:

- Double-tap a station to play it.
- The Actions rotor (swipe up or down) on a station has the same swipe action a sighted person gets: Remove on a favorite, Add to Favorites on a search result (or Remove, if it's already a favorite). The station that's playing also has Stop and Sleep Timer….
- To tidy up Favorites, tap Edit. Double-tapping a favorite then renames it, and its Actions rotor has Move Up, Move Down and Delete. Each move says the new position, such as "Position 3 of 12". Tap Done when you're finished. Rename is also in a favorite's touch-and-hold menu.
- Magic Tap (a two-finger double-tap) pauses and resumes from anywhere in the app.
- The Now Playing bar at the bottom of Favorites and Search pauses or resumes on a double-tap. Its Actions rotor has Stop, Next Station, Previous Station, and Sleep Timer…, which opens a pop-up list of timer lengths. The station that's playing has Stop and Sleep Timer… in its Actions rotor too.
- The Now Playing tab has the same controls as plain buttons, plus the sleep timer.
- The Favorites tab's More menu starts with a Sleep Timer submenu, so you can set the timer without leaving your favorites, followed by Import and Export.

## Requirements

- **Mac version:** macOS 13 Ventura or later, and Xcode or the Xcode Command Line Tools (for `swiftc`).
- **iPhone version:** iOS 17 or later; Xcode, signed in to your Apple ID (Xcode > Settings > Accounts); [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`); and an iPhone with Developer Mode turned on.

## Build the Mac version

There is no Xcode project for the Mac version. The build script compiles the sources with `swiftc` and produces an ad hoc signed app bundle. It works from any folder.

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

## Build the iPhone version

The iPhone version is described in `project.yml`. The script `ios.sh` turns that into an Xcode project with XcodeGen, builds it with `xcodebuild`, and installs it on a connected iPhone. You don't need to open Xcode.

1. Put your Apple team ID in a file named `ios-team.txt` in the project folder. It's the 10-character ID shown in Xcode > Settings > Accounts, or at [developer.apple.com/account](https://developer.apple.com/account). The file isn't uploaded to GitHub, so everyone uses their own.
2. Connect your iPhone with a cable and unlock it. The first time, tap Trust on the iPhone, then turn on Developer Mode (Settings > Privacy & Security > Developer Mode) and let it restart.
3. Build and install:

   ```bash
   bash ~/Projects/crystal-set/ios.sh install
   ```

   To build without installing:

   ```bash
   bash ~/Projects/crystal-set/ios.sh
   ```

4. With a free Apple ID (a "Personal Team"), the first time you open the app iOS says the developer isn't trusted. Go to Settings > General > VPN & Device Management, choose your Apple ID under Developer App, and choose Trust.

With a free Personal Team, an installed app stops opening after 7 days. Run `ios.sh install` again to renew it; your favorites are kept. A paid Apple Developer Program membership extends this to a year and adds TestFlight.

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
| Change sleep timer (Off, 15, 30, 45, 60, 90 minutes) | Command-T |
| Speak what's playing, including sleep time left | Command-I |
| Select the playing station in its list | Command-L |

The Command-arrow shortcuts are turned off while you're typing in a text field, so they still move the text cursor there.

### Station and File menus

| Action | Shortcut |
| --- | --- |
| Add or remove selected station from favorites | Command-D |
| Move favorite up / down | Command-Option-Up Arrow / Down Arrow |
| Show Favorites / Search | Command-1 / Command-2 |
| Find stations (focus search field) | Command-F |
| Add station by address (shows Search, ready to paste) | Command-N |
| Import favorites | Command-Shift-I |
| Export favorites | Command-Shift-E |

## Adding a station by its address

Paste or type the stream address into the Search field and press Return (on iPhone, tap Search). Anything starting with `http://` or `https://` is treated as an address rather than a search. It shows up as the only search result, so you can play it first, then add it to Favorites. On the Mac, File > Add Station (Command-N) jumps to an empty Search field, ready to paste into.

Crystal Set names the station after what the stream calls itself, when it says. Otherwise it uses the server's name, such as `radio.example.com`. If the address is already a favorite, that favorite is shown instead, so it isn't added twice.

## Renaming a favorite

- **Mac:** select the favorite, then click Rename… in the Favorites tab, choose Station > Rename Favorite…, or choose Rename… in the context menu (VO-Shift-M).
- **iPhone:** tap Edit in the Favorites tab, then double-tap the favorite. Or touch and hold it and choose Rename….

## Sleep timer

Choose a length from Controls > Sleep Timer, from the Sleep timer pop-up button next to the volume slider, or press Command-T to step through the choices. Crystal Set says the new setting each time. The sound fades out over the last 30 seconds, then playback stops. Command-I includes the time left, and pressing Stop turns the timer off. While the stream is paused, the timer waits too, and picks up where it left off when you resume.

## Importing favorites

File > Import Favorites accepts a JSON file in any of these formats:

- **Triode export:** an array of objects with `name`, `url`, `guid` and `description`. The bitrate, codec and country are read from the description.
- **Crystal Set's own favorites file** (see below)
- **Radio Browser API results:** an array of station objects with `stationuuid`

Stations already in your favorites (same ID or same stream address) are skipped.

## Exporting favorites

File > Export Favorites (or the Export button in the Favorites tab) saves your favorites as a JSON file, named "Crystal Set Favorites" by default. It uses Crystal Set's own format, which keeps every field and can be imported again, so it works as a backup or for moving favorites to another Mac.

## Where data is stored

Favorites are saved to `~/Library/Application Support/Crystal Set/favorites.json`. (Crystal Set was first called OTR Tuner. On first launch it copies favorites saved under that name.)

## Source layout

New to the code? Start with [How Crystal Set Works](docs/HOW-IT-WORKS.md), a guided tour for beginners, with things to try. Every source file also begins with a summary of what it does.

| File | Contents |
| --- | --- |
| `Shared/Models.swift` | Station model, Radio Browser client, app state and actions, VoiceOver announcements (Mac and iPhone) |
| `Shared/Player.swift` | Playback, stream titles, sleep timer, playlist links, media keys and Now Playing (Mac and iPhone) |
| `Shared/ImportExport.swift` | Importing and exporting favorites as JSON (Mac and iPhone) |
| `macOS/CrystalSetApp.swift` | Mac app entry point and menu commands |
| `macOS/ContentView.swift` | Mac window: Favorites and Search tabs, Now Playing bar, Rename sheet |
| `macOS/StationTable.swift` | Mac station table: VO-Space, Return, Space and double-click play, Command-Delete, context menu, VoiceOver actions |
| `macOS/Info.plist` | Mac app settings (name, ID, allowing http streams) |
| `iOS/CrystalSetPhoneApp.swift` | iPhone app entry point |
| `iOS/PhoneViews.swift` | iPhone screens: Favorites, Search, Now Playing, station rows with VoiceOver actions, Magic Tap |
| `iOS/Info.plist` | iPhone app settings, generated from `project.yml` |
| `build.sh` | Builds and installs the Mac version |
| `project.yml`, `ios.sh` | Describe, build and install the iPhone version |

## License

MIT. See [LICENSE](LICENSE).
