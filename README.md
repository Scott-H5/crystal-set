# Crystal Set

A small, VoiceOver-friendly internet radio app for the Mac and iPhone. It was built for old time radio (OTR) — mysteries, westerns, comedies and science fiction from radio's golden age — but it plays any internet radio stream. It's named after the crystal set, the simple home-built radio of the early broadcast era.

- Search the free [Radio Browser](https://www.radio-browser.info) station directory by tag or name
- Keep a reorderable list of favorite stations, and rename them
- Add any stream by pasting its address into the Search field, including `.pls` and `.m3u` playlist links
- Import favorites from a JSON file, including a [Triode](https://triode.app) favorites export, and export them as JSON
- Shows the current show title when the stream sends one
- Sleep timer (15 to 90 minutes) that fades the sound out over the last 30 seconds
- Works with the keyboard's media keys, the Lock Screen, and Control Center's Now Playing. Next and Previous step through your favorites, and on AirPods and EarPods a double press is Next and a triple press is Previous
- Reconnects on its own when a stream drops or goes silent: five tries over about 40 seconds. It says "Connection lost. Reconnecting" once, then "Reconnected" when sound is back
- On iPhone, picks the station back up after a phone call, Siri or an alarm, unless you paused it yourself

The Mac and iPhone versions share their stations, search, playback, sleep timer, and import and export code; only the screens differ. Favorites sync between your Mac and iPhone through iCloud (see [Syncing favorites with iCloud](#syncing-favorites-with-icloud)).

## Accessibility

Crystal Set uses only standard controls: tabs, tables and lists, buttons, text fields, pickers, and a slider. Nothing is custom-drawn; the few icons are Apple's built-in symbols. Every control has a plain text label. Important events are spoken through VoiceOver announcements: connecting, playing, paused, stopped, playback errors, search results, sleep timer changes, and changes to favorites.

On the Mac:

- The station that's playing has a speaker icon and a bold name in its list. VoiceOver reads it at the end of the name, such as "WOTR, now playing" (or "connecting" or "paused").
- In Search results, stations already in your favorites have a star. VoiceOver reads it as "favorite", so you know whether Command-D will add or remove.
- The Now Playing bar's Pause/Resume and Stop buttons show the usual playback icons. VoiceOver reads them by name, and hovering the pointer shows the name and shortcut.

On iPhone, with VoiceOver:

- Double-tap a station to play it.
- The Actions rotor (swipe up or down) on a station has the same swipe action a sighted person gets: Remove on a favorite, Add to Favorites on a search result (or Remove, if it's already a favorite). The station that's playing also has Stop and Sleep Timer….
- To tidy up Favorites, tap Edit. Double-tapping a favorite then renames it, and its Actions rotor has Move Up, Move Down and Delete. Each move says the new position, such as "Position 3 of 12". Tap Done when you're finished. Rename is also in a favorite's touch-and-hold menu.
- Magic Tap (a two-finger double-tap) pauses and resumes from anywhere in the app.
- The Now Playing bar at the bottom of Favorites and Search pauses or resumes on a double-tap. Its Actions rotor has Stop, Next Station, Previous Station, and Sleep Timer…, which opens a pop-up list of timer lengths. The station that's playing has Stop and Sleep Timer… in its Actions rotor too.
- The Now Playing tab has the same controls as plain buttons, plus the sleep timer.
- The Favorites tab's More menu starts with a Sleep Timer submenu, so you can set the timer without leaving your favorites, followed by Import and Export.

### Checking accessibility automatically

`audit.sh` runs Apple's automatic accessibility audit (the same checks as Xcode's Accessibility Inspector) on every screen, and prints one `AUDIT:` line per problem: elements VoiceOver can't name, low contrast, text that's cut off or doesn't grow with Larger Text, and so on.

```bash
~/dev/crystal-set/audit.sh ios
```

```bash
~/dev/crystal-set/audit.sh mac
```

- `ios` runs on a connected, unlocked iPhone, at the normal text size and the largest Accessibility size. The test opens Crystal Set and moves through its tabs by itself. It works with VoiceOver on: it touches, then double-taps, as a VoiceOver user would.
- `mac` runs on this Mac. The first time, macOS asks to let the test runner control the computer (System Settings > Privacy & Security > Accessibility). Turn that off again afterwards.
- A screenshot of each screen audited is saved in `build/audit-screenshots-ios` (or `-mac`), so each finding can be checked against what was actually on screen.

Known results that aren't problems: the Now Playing bar on iPhone stops growing at the largest standard text size on purpose (touch and hold it for the Large Content Viewer); rows scrolled underneath a bar are measured against the bar; and on the Mac, a few contrast and "missing action" results land on Apple's own pop-up menus and slider, whose text is plainly dark in the screenshots. The Mac tables' names also show as "unknown role": telling VoiceOver they're plain text silences that, but it stops VO-Space from playing a station, so it's left as it is.

## Requirements

- **Both versions:** Xcode, signed in to your Apple ID (Xcode > Settings > Accounts); [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`); and your Apple team ID in `ios-team.txt` (see step 1 under Build the iPhone version).
- **Mac version:** macOS 13 Ventura or later.
- **iPhone version:** iOS 17 or later, and an iPhone with Developer Mode turned on.

## Build the Mac version

Both versions are described in `project.yml`. `build.sh` turns that into an Xcode project with XcodeGen and builds the Mac version with `xcodebuild`, signed with your Apple team (the team ID in `ios-team.txt`). You don't need to open Xcode, and the script works from any folder.

Why it's signed with your team rather than "ad hoc": iCloud sync and TestFlight both need an app signed by an Apple Developer team. The first build may take a little longer, because Xcode creates your signing certificate.

Because the Mac app uses iCloud, it needs a development profile, and a Mac development profile lists the Macs it may run on. Register your Mac once at [developer.apple.com/account/resources/devices/add](https://developer.apple.com/account/resources/devices/add): choose macOS, and enter the Provisioning UDID from System Information > Hardware. Until then the build stops with "isn't registered in your developer account".

To build and install in one step:

```bash
bash ~/dev/crystal-set/build.sh install
```

This builds the app, quits Crystal Set if it's running, replaces the copy in `/Applications`, and reopens it if it was running.

To build without installing:

```bash
bash ~/dev/crystal-set/build.sh
```

The app is written to `build/mac/Build/Products/Release/CrystalSet.app` in the project folder. Installing copies it to Applications as `Crystal Set.app`.

(Adjust the path if you cloned the project somewhere other than `~/dev/crystal-set`.)

## Build the iPhone version

The iPhone version is described in `project.yml`. The script `ios.sh` turns that into an Xcode project with XcodeGen, builds it with `xcodebuild`, and installs it on a connected iPhone. You don't need to open Xcode.

1. Put your Apple team ID in a file named `ios-team.txt` in the project folder. It's the 10-character ID shown in Xcode > Settings > Accounts, or at [developer.apple.com/account](https://developer.apple.com/account). The file isn't uploaded to GitHub, so everyone uses their own.
2. Connect your iPhone with a cable and unlock it. The first time, tap Trust on the iPhone, then turn on Developer Mode (Settings > Privacy & Security > Developer Mode) and let it restart.
3. Build and install:

   ```bash
   bash ~/dev/crystal-set/ios.sh install
   ```

   To build without installing:

   ```bash
   bash ~/dev/crystal-set/ios.sh
   ```

4. With a free Apple ID (a "Personal Team"), the first time you open the app iOS says the developer isn't trusted. Go to Settings > General > VPN & Device Management, choose your Apple ID under Developer App, and choose Trust.

With a free Personal Team, an installed app stops opening after 7 days. Run `ios.sh install` again to renew it; your favorites are kept. A paid Apple Developer Program membership extends this to a year and adds TestFlight.

If Xcode keeps making 7-day profiles after your paid membership starts, it's reusing a profile it saved before. Move the Crystal Set profile out of `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` and build again; Xcode then fetches a one-year profile.

## Upload to TestFlight

With a paid Apple Developer Program membership and an app record in [App Store Connect](https://appstoreconnect.apple.com) for the bundle ID `io.github.scott-h5.crystalset`:

```bash
~/dev/crystal-set/testflight.sh ios
~/dev/crystal-set/testflight.sh mac
```

This makes a Release "archive" signed for distribution, then uploads it to App Store Connect, signed in as the Apple ID in Xcode > Settings > Accounts. No App Store Connect API key is needed. The first run creates your Apple Distribution certificate. Each upload gets the date and time as its build number, such as 202611121430, because App Store Connect refuses a build number it has already seen.

Apple then processes the build, usually in 5 to 30 minutes, and emails you. In App Store Connect, open the app's TestFlight tab and add yourself under Internal Testing; then install it with Apple's TestFlight app. Internal testers don't need App Review. TestFlight builds expire after 90 days, so upload a new one before then.

Both versions are the same app in App Store Connect, so the iPhone and Mac builds appear side by side in its TestFlight tab. Install the Mac build with the TestFlight app for the Mac.

## TestFlight from the terminal

`asc.sh` manages TestFlight through the App Store Connect API, so the App Store Connect website (hard to use with VoiceOver) is rarely needed:

```bash
~/dev/crystal-set/asc.sh status
```

| Command | What it does |
| --- | --- |
| `asc.sh status` | The newest iPhone and Mac builds and where each stands: processing, waiting for review, approved… |
| `asc.sh testers` | Who is in the external Testers group |
| `asc.sh add-tester EMAIL [FIRST LAST]` | Adds someone; TestFlight emails them an invitation once a build is approved |
| `asc.sh remove-tester EMAIL` | Removes someone |
| `asc.sh link` / `link on [LIMIT]` / `link off` | Shows, turns on (optionally capped at LIMIT testers) or turns off the public link anyone can join with |
| `asc.sh submit ios` / `submit mac` | Takes the newest build, adds the What to Test notes from `testflight-notes.txt`, gives it to the Testers group and sends it to Beta App Review. It waits for Apple to finish processing a fresh upload, and asks before sending. |

A new release is then: `testflight.sh ios`, then `asc.sh submit ios` (and the same with `mac`).

It needs an App Store Connect API key, created once under Users and Access > Integrations > App Store Connect API (Team Keys, App Manager role). The key file goes in `~/.appstoreconnect/private_keys/`, readable only by you (`chmod 600`); Apple lets you download it only once, so keep a backup somewhere safe. The key's settings go in `~/.appstoreconnect/crystal-set.env`:

```bash
ASC_KEY_ID=…              # the Key ID shown beside the key
ASC_ISSUER_ID=…           # the Issuer ID at the top of the keys page
ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_….p8"
ASC_APP_ID=…              # the number in the app's App Store Connect address
ASC_EXTERNAL_GROUP_ID=…   # the external group's ID, from its address
```

Nothing about the key is in this project, so it's never committed. `tools/asc.swift` explains how the API is signed and called.

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
| Next / previous station in the current list (wraps around at the ends) | Command-Right Arrow / Command-Left Arrow |
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
| Show Favorites (focus goes to the table) / Search (focus goes to the search field) | Command-1 / Command-2 |
| Find stations (focus search field) | Command-F |
| Add station by address (shows Search, ready to paste) | Command-N |
| Import favorites | Command-Shift-I |
| Export favorites | Command-Shift-E |

## Pinned stations

Pin up to ten favorites to keep them one step away:

- **iPhone and iPad:** a station's Actions rotor (swipe up or down) and its touch-and-hold menu have **Pin to Top** and **Unpin**. Pinned stations appear as large buttons under a **Pinned** heading at the top of Favorites (VoiceOver's Headings rotor jumps there); double-tap one to play it. The buttons have the same Actions rotor as the list: Remove, Unpin, and Stop and Sleep Timer… on the station that's playing. They fit the screen: two across on an iPhone, more on an iPad or in landscape, one per row at the largest text sizes.
- **Mac:** Station > Pin to Top (Command-Shift-P), the table's context menu (VO-Shift-M) or VoiceOver actions (VO-Command-Space), or the Pin to Top button. Pinned stations appear as numbered buttons above the table, and **Command-Option-1** to **9**, then **0** for the tenth, play them from anywhere (Controls menu). In the table, VoiceOver adds "pinned" after the name.

Pinned stations stay in the Favorites list too, and their order follows it: move a favorite up or down to reorder the pins. Pins sync through iCloud with your favorites. If ten are already pinned, unpin one first.

## Filtering favorites

The **Filter favorites** field at the top of Favorites narrows the list to stations whose name, country, format or tags contain what you type. While filtering, the Pinned row is hidden and moving favorites is turned off (a place in the filtered list isn't a place in the full one). Clear the field to see everything again.

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

## Syncing favorites with iCloud

Favorites sync between every copy of Crystal Set signed in to the same iCloud account (with iCloud Drive turned on). Adding, removing, renaming, moving or importing a favorite reaches your other devices, usually within a few seconds to a minute.

Each device also keeps its own copy, so Crystal Set works offline and without iCloud. The shared copy is kept in iCloud's key-value storage, Apple's simple sync for small data, under your team ID and the bundle ID; both apps ask for it in their `CrystalSet.entitlements` file.

- The first time a device meets the list in iCloud, it merges: iCloud's stations in their order, then any of the device's own stations that were missing. So turning sync on for two devices that each have favorites loses neither list.
- After that, the newest change wins. Each list carries the date and time someone last changed it, and devices compare those dates. The newer list replaces the older one, so removing a station on one device removes it everywhere.
- Opening the app doesn't count as a change, so a device that was closed or offline for a while takes the newer list instead of sending its old one. (The first sync builds got this wrong: opening the app on one device could overwrite changes made on another.)
- If both devices change the list while one is offline, the change made last wins when they reconnect.

The code, with these rules in comments, is under "iCloud sync" in `Shared/Models.swift`.

## Where data is stored

On the Mac, favorites are saved to `~/Library/Containers/io.github.scott-h5.crystalset/Data/Library/Application Support/Crystal Set/favorites.json`. On the iPhone, they're saved in the app's own storage.

The Mac version runs in the App Sandbox, which Apple requires for TestFlight and the App Store. A sandboxed app can only use its own folder (the `Containers` path above), the internet, and files you pick in an Open or Save panel; `macOS/CrystalSet.entitlements` lists those permissions. Before the sandbox, the Mac kept favorites in `~/Library/Application Support/Crystal Set/`. The first time the sandboxed version opens, macOS moves that folder into the sandbox (see `macOS/container-migration.plist`). macOS also stops other apps, including Terminal, from opening the sandbox folder, so use File > Export Favorites to get a copy.

(Crystal Set was first called OTR Tuner. On first launch it copies favorites saved under that name.)

## App icon

The icon is a crystal set, the simple home-built radio the app is named after: a copper coil of wire on a deep blue background, a pale blue crystal standing on the coil, and radio waves spreading out to both sides of the crystal's tip. It's drawn from basic shapes by `icon/make-icon.swift`, so it's original artwork, with no clip art or Apple symbols. To change it, edit that file, then run:

```bash
bash ~/dev/crystal-set/icon/make-icon.sh
```

This writes the iPhone icon (`iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png`) and the Mac icon (`macOS/AppIcon.icns`). Rebuild both versions afterward.

## Source layout

New to the code? Start with [How Crystal Set Works](docs/HOW-IT-WORKS.md), a guided tour for beginners, with things to try. Every source file also begins with a summary of what it does.

| File | Contents |
| --- | --- |
| `Shared/Models.swift` | Station model, Radio Browser client, app state and actions, VoiceOver announcements (Mac and iPhone) |
| `Shared/Player.swift` | Playback, stream titles, sleep timer, playlist links, media keys and Now Playing (Mac and iPhone) |
| `Shared/ImportExport.swift` | Importing and exporting favorites as JSON (Mac and iPhone) |
| `macOS/CrystalSetApp.swift` | Mac app entry point and menu commands |
| `macOS/ContentView.swift` | Mac window: Favorites and Search tabs, Now Playing bar, Rename sheet |
| `macOS/StationTable.swift` | Mac station table: VO-Space, Return, Space and double-click play, Command-Delete, context menu, VoiceOver actions, playing and favorite icons |
| `macOS/Info.plist` | Mac app settings (name, ID, allowing http streams) |
| `iOS/CrystalSetPhoneApp.swift` | iPhone app entry point |
| `iOS/PhoneViews.swift` | iPhone screens: Favorites, Search, Now Playing, station rows with VoiceOver actions, Magic Tap |
| `iOS/Info.plist` | iPhone app settings, generated from `project.yml` |
| `build.sh` | Builds and installs the Mac version |
| `project.yml`, `ios.sh` | Describe, build and install the iPhone version |

## Privacy

Crystal Set collects nothing about you: no accounts, analytics, advertising or tracking. See the [privacy policy](PRIVACY.md) for what the app sends to Radio Browser, to radio stations and to your own iCloud.

## License

MIT. See [LICENSE](LICENSE).
