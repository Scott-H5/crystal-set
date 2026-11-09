# How Crystal Set Works

A guided tour of the code, for anyone who wants to read it, understand it, or try changing it. No programming experience is assumed.

Crystal Set is written in **Swift**, Apple's programming language. It comes in two versions, for the Mac and for iPhone, which share most of their code. Both use **SwiftUI** to describe their screens. The Mac version also uses **AppKit** (the Mac's older toolkit) for its station tables.

## Contents

1. Before you start: opening, rebuilding, and undoing
2. The big picture
3. What happens when you press Play
4. How VO-Space plays a station
5. How favorites are saved
6. One app, two platforms
7. Swift words you'll meet
8. Things to try
9. When the build fails
10. Learning more

## 1. Before you start: opening, rebuilding, and undoing

### Opening the code

The code is in three folders inside the project folder, `~/Projects/crystal-set`:

- `Shared`: code both versions use.
- `macOS`: the Mac's window, menus and tables.
- `iOS`: the iPhone's screens.

Each file ends in `.swift` and is plain text.

Any plain-text editor works, with one warning: **TextEdit replaces straight quotes with curly "smart" quotes**, and Swift rejects those. If you use TextEdit, open Format and choose Make Plain Text, then open Edit, then Substitutions, and turn off Smart Quotes and Smart Dashes. BBEdit (free to use) and Xcode don't have this problem, and both work with VoiceOver.

Every file begins with a few comment lines saying what it's for, and the file's sections are marked with lines beginning `// MARK: -`. Lines beginning `//` or `///` are comments for people; Swift ignores them.

### Rebuilding after a change

```bash
bash ~/Projects/crystal-set/build.sh install
```

This builds the Mac app and installs it in Applications. If the app is running, it quits it first and reopens it afterwards. If you made a mistake, the build stops and shows an error instead; see section 9.

For the iPhone, connect it with a cable, unlock it, and run:

```bash
bash ~/Projects/crystal-set/ios.sh install
```

A change in the `Shared` folder affects both versions, so rebuild both to try it.

### Undoing an experiment

The project uses **git**, which remembers every saved version. Nothing you try can be lost or break anything for good.

To see which files you've changed:

```bash
git -C ~/Projects/crystal-set status
```

To see exactly what changed, line by line:

```bash
git -C ~/Projects/crystal-set diff
```

To throw away all your changes and go back to the last saved version:

```bash
git -C ~/Projects/crystal-set restore .
```

Then rebuild, and the app is back to normal.

## 2. The big picture

| File | What it does |
| --- | --- |
| `Shared/Models.swift` | The app's data and decisions: what a Station is, searching Radio Browser (or looking up a pasted stream address), the favorites list, and the actions (play, add, remove, rename, move, next station, volume). Also `announce(_:)`, which makes VoiceOver speak. |
| `Shared/Player.swift` | Sound: playing a stream, the playing/paused/stopped status, show titles, the sleep timer, the media keys and Lock Screen controls, and opening playlist links. |
| `Shared/ImportExport.swift` | Reading and writing favorites as JSON files. |
| `macOS/CrystalSetApp.swift` | Where the Mac version starts. Creates the AppModel, opens the window, and defines the menus and keyboard shortcuts. |
| `macOS/ContentView.swift` | What's in the Mac window: the Favorites and Search tabs, the Now Playing bar, the Rename sheet, and the Import/Export panels. |
| `macOS/StationTable.swift` | The Mac's two station tables, including the keys and VoiceOver behavior on table rows. |
| `iOS/CrystalSetPhoneApp.swift` | Where the iPhone version starts. Creates the AppModel and shows the tabs. |
| `iOS/PhoneViews.swift` | The iPhone's screens: the Favorites, Search and Now Playing tabs, station rows and their VoiceOver actions, the Now Playing bar, and the Rename alert. |
| `project.yml` | Describes the iPhone version for XcodeGen, which turns it into an Xcode project. |
| `build.sh`, `ios.sh` | Build (and install) the Mac and iPhone versions. |

The files work together like this:

- **The AppModel is in charge.** It lives in `Models.swift`, and there's exactly one, created when the app starts. It holds the favorites, search results, what's selected, and which tab is showing.
- **The Player handles sound.** The AppModel owns it and asks it to play, pause and stop.
- **The screens only show and ask.** The views (in `macOS/ContentView.swift` and `macOS/StationTable.swift` on the Mac, `iOS/PhoneViews.swift` on iPhone) display what's in the AppModel and Player. Their buttons call functions on the AppModel or Player to get things done. The views themselves make no decisions.
- **Changes flow back automatically.** When the AppModel or Player changes something marked `@Published`, SwiftUI updates whatever shows it. Nothing has to tell the window to refresh.

## 3. What happens when you press Play

Here's the whole journey on the Mac, from pressing Return on a favorite to hearing sound. (On iPhone, steps 1 and 2 are a double-tap on a `StationRow` in `iOS/PhoneViews.swift`, which calls `model.play(_:)` directly; from step 3 on, it's the same shared code.) Each step names the file and function, so you can follow along in the code.

1. **The table notices the key.** `StationTable.swift`, in `StationNSTableView`, function `keyDown(with:)`. Every key pressed in the table comes here. Key number 36 is Return, so it calls `coordinator.play(row:)` with the selected row.
2. **The coordinator finds the station.** `StationTable.swift`, `Coordinator.play(row:)`. It looks up which Station is in that row and calls `model.play(_:)`.
3. **The AppModel passes it on.** `Models.swift`, `AppModel.play(_:)`. It tells the Player to play the station. If the station came from Radio Browser, it also tells Radio Browser it was played, in the background.
4. **The Player starts connecting.** `Player.swift`, `Player.play(_:)`. It stops anything already playing, sets the state to "Connecting…", and asks VoiceOver to say "Connecting to …". Then it starts a background job.
5. **Playlist links are opened.** `Player.swift`, `StreamResolver.resolve(_:)`. If the address is a playlist (`.pls`, `.m3u` or `.asx`), it downloads the playlist and finds the real stream address inside.
6. **AVPlayer starts streaming.** `Player.swift`, `Player.start(_:)`. AVPlayer is Apple's player, and it does the actual streaming. The Player also starts listening for show titles and for failure.
7. **Sound arrives.** `Player.swift`, `timeControlChanged(_:)`. AVPlayer reports that it's playing. The Player sets the state to "Playing" and VoiceOver says "Playing …".
8. **The window updates itself.** Because `state` and `station` are `@Published`, the Now Playing bar in `ContentView.swift` redraws with the new name and status, and the Pause button's title updates too.

If the stream can't be opened, step 6 calls `fail(_:)` instead. That sets the state to "Could not play: …", with the reason.

## 4. How VO-Space plays a station

In VoiceOver, VO-Space performs an item's default action. On a table row, VoiceOver's default action is to *select* the row, not to press it. So the table can't simply wait for a press.

The trick is in how the selection arrives. When you select a row with the arrow keys or the mouse, the table changes its own selection. When VoiceOver selects a row, it goes through the accessibility interface instead: it calls `setAccessibilitySelectedRows(_:)` on the table, or `setAccessibilitySelected(_:)` on the row. Crystal Set replaces both functions (`StationTable.swift`, in `StationNSTableView` and `StationRowView`). Each one does the normal selection and then plays the station.

Both functions can fire for the same VO-Space press, so `Coordinator.accessibilitySelected(row:)` ignores a second request for the same row within a second.

## 5. How favorites are saved

- **Where:** `~/Library/Application Support/Crystal Set/favorites.json`.
- **When:** every time the list changes. In `Models.swift`, the `favorites` property has a `didSet` that calls `saveFavorites()`. `didSet` runs whenever the value changes, so every add, remove, move or import saves straight away.
- **Loading:** when the app starts, `AppModel`'s `init()` reads the file back.
- **Format:** a JSON list of stations. Because `Station` is marked `Codable`, Swift converts between a Station and its JSON automatically.

## 6. One app, two platforms

The Mac and iPhone versions are built from the same `Shared` code plus their own screens:

- **Mac:** `build.sh` compiles `Shared` and `macOS` together with `swiftc`.
- **iPhone:** `ios.sh` builds `Shared` and `iOS` together. It uses an Xcode project that XcodeGen creates from `project.yml`.

Where the shared code needs to differ, it's marked like this:

```swift
#if os(macOS)
// lines used only on the Mac
#else
// lines used only on iPhone
#endif
```

There are only a few of these. They cover how VoiceOver announcements are sent (`announce(_:)` in `Shared/Models.swift`), the iPhone's audio session, which keeps audio playing when the screen locks, the starting volume, and one Mac-only Now Playing setting (all in `Shared/Player.swift`).

**Signing:** an iPhone only runs apps signed by a known developer. `ios.sh` signs Crystal Set with the Apple team whose ID is in `ios-team.txt`. That file isn't in git, so anyone who downloads the project uses their own team. With a free Apple ID (a "Personal Team"), the app stops opening after 7 days. Running `ios.sh install` again renews it.

## 7. Swift words you'll meet

- **`let` and `var`:** a named value. A `let` never changes once it's set, and a `var` can change.
- **`func`:** a function, a named piece of code that does one job, such as `func stop()`. Some take inputs, written in parentheses: `func play(_ station: Station)`.
- **`struct`:** a bundle of related values, such as `Station`, which holds a name, a URL, a country and so on. Every view is a struct too.
- **`class`:** like a struct, but shared. Everyone holding it sees the same one. `AppModel` and `Player` are classes, so every screen sees the same favorites and the same player.
- **`enum`:** a fixed list of choices, such as `Player.State`: stopped, connecting, playing, paused or failed.
- **Optional (`?`) and `nil`:** a `?` after a type means the value might be missing. `nil` means "missing". `Station?` is "a station, or nothing".
- **`if let` and `guard let`:** these check whether an optional has a value, and use it if so. `guard` also leaves the function early when the check fails.
- **`??`:** "or else". `name ?? "Unnamed station"` means use the name, or "Unnamed station" if there's no name.
- **`$0`:** inside braces like `{ $0.id == id }`, `$0` means "the item being looked at". For example, `favorites.first { $0.id == id }` finds the first favorite whose ID matches.
- **Closure (code in braces):** code stored to run later. A button's action, `Button("Stop") { player.stop() }`, is a closure.
- **`@Published`:** marks a value the screens watch. When it changes, they update.
- **`@State` and `@Binding`:** `@State` is a value a view keeps for itself, such as the text typed in a field. A binding (written with `$`, like `$model.query`) connects a control to a value in both directions, so typing changes the value and changing the value changes the field.
- **`async` and `await`:** code that waits, for the network or a timer, without freezing the app. `await` marks the waiting point.
- **`Task { }`:** starts work running in the background.
- **`throws`, `try`, `do` / `catch`:** a function marked `throws` can fail with an error. You call it with `try`. In a `do` block, if anything fails, the `catch` block runs instead. `try?` means "try, and if it fails, just give me nothing".
- **`extension`:** adds more functions to a type defined somewhere else. `ImportExport.swift` uses one to add the import and export functions to `AppModel`.
- **`@MainActor`:** "run on the main thread". All user interface work must happen there.
- **`private`:** only usable inside this file or type. `private(set)` means other files can read the value but not change it.
- **`override`:** replaces a standard function with a custom version. Calling `super.` runs the standard version as well.
- **`#if os(macOS)` … `#else` … `#endif`:** includes some lines only when building for one platform (see section 6).

## 8. Things to try

Each of these is a small, safe change. To find the spot, open the file and use Find to search for the text shown. Line numbers are given too, but they shift as the code changes. After each change, rebuild. Files in `Shared` affect both the Mac and the iPhone. To put things back, use `git restore .` (see section 1).

### Change the sleep timer choices

In `Shared/Player.swift` (around line 207), search for `sleepTimerChoices`:

```swift
static let sleepTimerChoices = [15, 30, 45, 60, 90]
```

Change the numbers to any minutes you like, for example `[10, 20, 30, 60, 120]`. The Mac's Sleep Timer submenu, pop-up button and Command-T, and the iPhone's Sleep Timer picker, all update to match, because they all read this one list.

### Change how long the sleep timer fades

In `Shared/Player.swift` (around line 215), search for `sleepFadeDuration`:

```swift
var sleepFadeDuration: TimeInterval = 30
```

The 30 is seconds. Try 60 for a longer, gentler fade.

### Change the search the app starts with

In `Shared/Models.swift` (around line 260), search for `var query`:

```swift
@Published var query = "old time radio"
```

Change the words between the quotes, for example to `"radio drama"`.

### Change the starting volume

In `Shared/Player.swift` (around line 62), search for `Double = 0.8`:

```swift
@Published var volume: Double = 0.8 {
```

Volume runs from 0 (silent) to 1 (full), so 0.8 is 80%. Try 0.5 for 50%. This is the Mac's starting volume. A few lines above, inside `#if os(iOS)`, the iPhone's is 1.0, since the phone's volume buttons set the level.

### Change the volume step

This one takes three edits, because the step appears in three places. It's a good example of following one idea through the code.

1. In `macOS/CrystalSetApp.swift` (around lines 106 and 109), search for `changeVolume`. Change `0.05` to `0.02` in Volume Up, and `-0.05` to `-0.02` in Volume Down. That gives 2% steps.
2. In `Shared/Models.swift` (around line 440), search for `* 20`. The volume is rounded to steps of 1/20, which is 5%. For 2% steps, change both 20s to 50, since 1/50 is 2%.
3. In `macOS/ContentView.swift` (around line 269), search for `step: 0.05`. Change it to `0.02` so the slider matches.

### Add a keyboard shortcut

To add a Controls menu item that sets the volume to 50% with Command-0 (Mac only, since the iPhone has no menus), open `macOS/CrystalSetApp.swift` and search for `Button("Reconnect")` (around line 90). After the line ending in `.keyboardShortcut("r")`, add these two lines:

```swift
            Button("Half Volume") { model.player.volume = 0.5 }
                .keyboardShortcut("0")
```

- `Button("Half Volume")` is the menu item's name.
- The code in braces is what it does.
- `.keyboardShortcut("0")` makes it Command-0.

Rebuild, and it's in the Controls menu. To speak the new level too, use `{ model.player.volume = 0.5; announce("Volume 50 percent") }`.

### Change the most search results shown

In `Shared/Models.swift` (around line 180), search for `"limit"`:

```swift
URLQueryItem(name: "limit", value: "200"),
```

Change `"200"` to another number. Keep the quotes; the web address needs text.

## 9. When the build fails

If a change has a mistake in it, `build.sh` (or `ios.sh`) stops and prints an error instead of building. Errors look like this:

```
Shared/Player.swift:207:52: error: expected ']' in array literal
```

That means: in `Shared/Player.swift`, line 207, about 52 characters in, there's a problem. The text after `error:` describes it.

Common causes:

- **A missing or extra bracket, brace or quote.** Every `(`, `[`, `{` and `"` needs its partner.
- **Curly quotes.** Smart quotes from TextEdit look right but aren't the `"` that Swift expects.
- **A misspelled name.** Swift is exact about spelling and capital letters, so `Volume` and `volume` are different names.
- **The error appears after the real mistake.** Sometimes Swift only notices a problem a line or two later, so check the lines just before the one it names.

If you're stuck, `git diff` shows exactly what you changed, and `git restore .` puts everything back.

## 10. Learning more

- **[The Swift Programming Language](https://docs.swift.org/swift-book/)** is Apple's free book about Swift. Its "A Swift Tour" chapter is a good first read.
- **[Swift Playgrounds](https://www.apple.com/swift/playgrounds/)** is a free Apple app for learning Swift by trying it, a few lines at a time.
- **Apple's [SwiftUI tutorials](https://developer.apple.com/tutorials/swiftui)** cover how screens like Crystal Set's window are built.
- **Ask questions about the code.** Pick any file, function or line and ask what it does. The comments are a starting point, not the last word.
