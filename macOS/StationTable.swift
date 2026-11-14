// StationTable.swift
//
// The Favorites and Search results tables.
//
// Most of the app uses SwiftUI, but these tables use AppKit, the Mac's
// older and more detailed user interface toolkit. SwiftUI's own Table can't
// tell when VoiceOver selects a row, and that's what makes VO-Space play a
// station. So this file builds a standard AppKit table (NSTableView) and
// wraps it so SwiftUI screens can use it like any other view.
//
// The pieces:
//   - StationTable: the wrapper SwiftUI uses. It creates the table and
//     keeps it in step with the station list and the selection.
//   - Coordinator: answers the table's questions ("how many rows?", "what
//     goes in this cell?") and carries out actions (play, add, remove).
//   - StationNSTableView: the table itself, with extra keys (Return, Space,
//     Command-Delete) and the VoiceOver selection check.
//   - StationRowView: one row, with VoiceOver's actions and menu.
//   - StationNameCellView: the Name cell, with a speaker icon on the playing
//     station and (in Search results) a star on stations already in Favorites.

import AppKit
import SwiftUI

// MARK: - Station table

/// A standard AppKit table of stations, wrapped for SwiftUI.
///
/// AppKit is used here (instead of SwiftUI's Table) so the table can tell when
/// VoiceOver selects a row (VO-Space) and play that station. The table also
/// plays on Return, Space, or double-click; Command-Delete removes a favorite; and it
/// has a context menu (VO-Shift-M) and VoiceOver actions (VO-Command-Space)
/// with Play and Add to / Remove from Favorites.
///
/// `NSViewRepresentable` is SwiftUI's way of hosting an AppKit view.
struct StationTable: NSViewRepresentable {
    @EnvironmentObject private var model: AppModel
    // The stations to list, and which one is selected (shared with the AppModel).
    let stations: [Station]
    @Binding var selection: Station.ID?
    // What VoiceOver calls the table: "Favorites" or "Search results".
    let title: String
    /// Command-Delete removes the selected station (Favorites only).
    var allowsDelete = false
    /// Takes keyboard focus when the AppModel's focusFavoritesTable is set
    /// (Command-1). Favorites only.
    var answersFocusRequests = false
    /// Stars stations that are already favorites. On for Search results only,
    /// since every row in Favorites would have one.
    var showsFavoriteStars = false
    // The player, watched so the speaker icon moves when another station
    // plays. (`@ObservedObject` makes SwiftUI call updateNSView when it changes.)
    @ObservedObject var player: Player

    // SwiftUI calls this once to create the helper object.
    func makeCoordinator() -> Coordinator { Coordinator() }

    // SwiftUI calls this once to build the table.
    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        coordinator.parent = self

        // Set up the table. The coordinator supplies its rows (dataSource)
        // and responds to what happens in it (delegate).
        let table = StationNSTableView()
        table.coordinator = coordinator
        table.dataSource = coordinator
        table.delegate = coordinator
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.style = .inset
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        // Double-clicking a row calls doubleClicked(_:) on the coordinator.
        table.target = coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.setAccessibilityLabel(title)

        // One column for each case of the Column enum below.
        for column in Column.allCases {
            let tableColumn = NSTableColumn(identifier: column.identifier)
            tableColumn.title = column.rawValue
            tableColumn.minWidth = column.minWidth
            tableColumn.width = column.width
            table.addTableColumn(tableColumn)
        }

        // An empty context menu; the coordinator fills it in each time it
        // opens (see menuNeedsUpdate), so it fits the row it opened on.
        let menu = NSMenu()
        menu.delegate = coordinator
        table.menu = menu

        // Put the table in a scroll view so long lists can scroll.
        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        // Load the rows now. The table may already have asked for its row
        // count (and been told zero) when its data source was set above, and
        // updateNSView only reloads when the station list changes.
        coordinator.table = table
        coordinator.stations = stations
        coordinator.reload()
        coordinator.syncSelection()
        return scrollView
    }

    // SwiftUI calls this whenever something the table shows may have changed.
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.table?.setAccessibilityLabel(title)
        // Reload only when the list really changed, so VoiceOver doesn't lose its place.
        if coordinator.stations != stations {
            coordinator.stations = stations
            coordinator.reload()
        }
        coordinator.syncSelection()
        // Move the speaker icon and stars if playback or favorites changed.
        coordinator.refreshNameCells()

        // Command-1 asked for focus on this table. Wait a moment first: when
        // the tab has only just switched, the table isn't in the window yet.
        // (The model is changed only after this function returns, because
        // SwiftUI doesn't allow changes while it's updating the screen.)
        if answersFocusRequests && model.focusFavoritesTable {
            let model = self.model
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let table = coordinator.table, let window = table.window {
                    window.makeFirstResponder(table)
                }
                model.focusFavoritesTable = false
            }
        }
    }

    // MARK: Columns

    /// The table's columns, in order. The text after `=` is the column heading.
    enum Column: String, CaseIterable {
        case name = "Name"
        case country = "Country"
        case format = "Format"
        case tags = "Tags"

        // AppKit names columns with an "identifier"; reuse the heading.
        var identifier: NSUserInterfaceItemIdentifier { .init(rawValue) }

        // The narrowest each column may be, in points.
        var minWidth: CGFloat {
            switch self {
            case .name: return 140
            case .country, .format, .tags: return 70
            }
        }

        // Each column's starting width, in points.
        var width: CGFloat {
            switch self {
            case .name: return 260
            case .country: return 150
            case .format: return 100
            case .tags: return 200
            }
        }

        // What each column shows for a station.
        func text(for station: Station) -> String {
            switch self {
            case .name: return station.name
            case .country: return station.country
            case .format: return station.formatDescription
            case .tags: return station.tags
            }
        }
    }

    // MARK: Coordinator

    /// The table's helper. AppKit tables don't hold their own data; they ask
    /// a "data source" for it, row by row, and report events to a "delegate".
    /// This object is both, and it carries out the table's actions.
    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        // The SwiftUI wrapper, for reaching the AppModel and the selection.
        var parent: StationTable?
        // `weak` avoids the table and coordinator keeping each other alive forever.
        weak var table: NSTableView?
        var stations: [Station] = []
        // True while this code changes the table itself, so those changes
        // aren't mistaken for the person's.
        private var isSyncing = false

        private var model: AppModel? { parent?.model }

        // The station in a given row, or nil if there's no such row.
        // Rows are numbered from 0.
        func station(at row: Int) -> Station? {
            stations.indices.contains(row) ? stations[row] : nil
        }

        func reload() {
            isSyncing = true
            table?.reloadData()
            isSyncing = false
        }

        /// Makes the table's selection match the SwiftUI selection.
        /// (For example, after Command-Right Arrow selects the next station.)
        func syncSelection() {
            guard let table else { return }
            // The row that should be selected, or nil for none.
            let wanted = parent?.selection.flatMap { id in stations.firstIndex { $0.id == id } }
            // Already right? Nothing to do. (`selectedRow` is -1 when nothing is selected.)
            guard wanted != (table.selectedRow >= 0 ? table.selectedRow : nil) else { return }
            isSyncing = true
            if let wanted {
                table.selectRowIndexes(IndexSet(integer: wanted), byExtendingSelection: false)
                table.scrollRowToVisible(wanted)
            } else {
                table.deselectAll(nil)
            }
            isSyncing = false
        }

        // MARK: Actions

        // Return, double-click, VO-Space, and the menu's Play.
        func play(row: Int) {
            guard let station = station(at: row) else { return }
            select(row: row)
            model?.play(station)
        }

        /// Space: plays the station, or pauses and resumes it if it is already playing.
        func playOrPause(row: Int) {
            guard let station = station(at: row) else { return }
            select(row: row)
            model?.playOrPause(station)
        }

        /// VoiceOver selects rows through the accessibility API rather than
        /// the keyboard or mouse, in two different situations:
        ///
        ///   1. Moving the VoiceOver cursor (VO-Up/Down Arrow, or VO-Left/Right
        ///      Arrow past the end of a row). With "keyboard focus follows the
        ///      VoiceOver cursor" on (VoiceOver's default), VoiceOver selects
        ///      each row it lands on. That must NOT play: it's just browsing.
        ///   2. VO-Space on a row. That should play.
        ///
        /// Both arrive the same way, so the difference is whether the row was
        /// already selected. Moving the cursor selects a new row; VO-Space
        /// selects the row the cursor (and so the selection) is already on.
        /// If the VoiceOver cursor isn't following focus, the first VO-Space
        /// on a row selects it and a second one plays it.
        ///
        /// `wasSelected` is whether the row was selected just before this
        /// report. Both the table and the row may report the same selection
        /// (the second report sees the row already selected), so any repeat
        /// for the same row within half a second is ignored.
        func accessibilitySelected(row: Int, wasSelected: Bool) {
            let now = Date()
            if row == lastAccessibilityRow, now.timeIntervalSince(lastAccessibilityTime) < 0.5 { return }
            lastAccessibilityRow = row
            lastAccessibilityTime = now
            if wasSelected {
                play(row: row)
            }
            // Otherwise VoiceOver just moved to this row; the selection has
            // already changed (and been passed to SwiftUI), and nothing plays.
        }
        // The last row VoiceOver selected, and when.
        private var lastAccessibilityRow = -1
        private var lastAccessibilityTime = Date.distantPast

        // Command-Delete, in the Favorites table only.
        func delete(row: Int) {
            guard parent?.allowsDelete == true, let station = station(at: row) else { return }
            model?.removeFromFavorites(station)
        }

        // The menu's and VoiceOver actions' Add to / Remove from Favorites.
        func toggleFavorite(row: Int) {
            guard let station = station(at: row), let model else { return }
            if model.isFavorite(station) {
                model.removeFromFavorites(station)
            } else {
                model.addToFavorites(station)
            }
        }

        // The context menu's Rename…, in the Favorites table only. Opens the
        // Rename sheet. (Not among the VoiceOver actions, to keep that list short.)
        @objc func menuRename(_ sender: NSMenuItem) {
            guard parent?.allowsDelete == true, let station = station(at: sender.tag) else { return }
            model?.renamingStation = station
        }

        // VoiceOver's Move Up and Move Down, in the Favorites table only.
        // True if the favorite in this row can move by `offset` (-1 up,
        // +1 down): not the first one up, or the last one down.
        func canMoveFavorite(row: Int, by offset: Int) -> Bool {
            guard parent?.allowsDelete == true, let model, !model.isFilteringFavorites else { return false }
            return model.favorites.indices.contains(row + offset)
        }

        // Selects the row and moves it, using the same code as the Move Up
        // and Move Down buttons and menu items (which also says the new
        // position, such as "Position 3 of 10"). Rows remember their station
        // rather than their number, so the VoiceOver cursor moves with it.
        func moveFavorite(row: Int, by offset: Int) {
            guard canMoveFavorite(row: row, by: offset),
                  let station = station(at: row), let model else { return }
            model.favoriteSelection = station.id
            model.moveSelectedFavorite(by: offset)
        }

        /// "Pin to Top" or "Unpin" for a favorite, or nil in Search results
        /// (pins are for favorites).
        func pinActionTitle(row: Int) -> String? {
            guard parent?.allowsDelete == true, let station = station(at: row), let model else { return nil }
            return model.isPinned(station) ? "Unpin" : "Pin to Top"
        }

        func togglePin(row: Int) {
            guard let station = station(at: row) else { return }
            model?.togglePin(station)
        }

        func favoriteActionTitle(row: Int) -> String {
            if let station = station(at: row), model?.isFavorite(station) == true {
                return "Remove from Favorites"
            }
            return "Add to Favorites"
        }

        private func select(row: Int) {
            guard let table, table.selectedRow != row else { return }
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        // `@objc` lets AppKit's older (Objective-C) machinery call this.
        // `clickedRow` is the row that was double-clicked, or -1 for none.
        @objc func doubleClicked(_ sender: NSTableView) {
            if sender.clickedRow >= 0 { play(row: sender.clickedRow) }
        }

        // MARK: Data source and delegate

        // The table asks: how many rows?
        func numberOfRows(in tableView: NSTableView) -> Int { stations.count }

        // The table asks: what goes in this column of this row? The answer is
        // a cell view holding a text label.
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, let column = Column(rawValue: tableColumn.identifier.rawValue),
                  let station = station(at: row) else { return nil }

            // The Name column has its own cell, with room for the icons.
            if column == .name {
                let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: nil)
                    as? StationNameCellView ?? StationNameCellView(identifier: tableColumn.identifier)
                configure(cell, for: station)
                return cell
            }

            // Reuse a cell that has scrolled out of sight if there is one;
            // otherwise make a new one.
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: tableColumn.identifier, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                // PressableCellView passes VO-Space on to the row (see below).
                cell = PressableCellView()
                cell.identifier = tableColumn.identifier
                // A plain text label. Text too long for the column ends in "…".
                // SpokenTextField lets an empty cell say "None" to VoiceOver.
                let field = SpokenTextField(labelWithString: "")
                field.lineBreakMode = .byTruncatingTail
                field.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(field)
                cell.textField = field
                // Layout rules: fill the cell's width (2 points in from each
                // side) and sit in the middle vertically.
                NSLayoutConstraint.activate([
                    field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                    field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            let text = column.text(for: station)
            cell.textField?.stringValue = text
            // An empty cell (a station with no tags, say) reads "None" to
            // VoiceOver instead of nothing. Apple's audit flagged the empty
            // cells as having no description.
            (cell.textField as? SpokenTextField)?.spokenText = text.isEmpty ? "None" : nil
            // Hovering the pointer shows the full text.
            cell.textField?.toolTip = text.isEmpty ? nil : text
            return cell
        }

        // MARK: Speaker icon and stars

        /// Whether a station is the one playing, and how, for its speaker icon.
        /// Nil means no icon: another station is playing, or nothing is.
        func playMark(for station: Station) -> StationNameCellView.PlayMark? {
            guard let player = parent?.player, player.station?.id == station.id else { return nil }
            switch player.state {
            case .playing: return .playing
            case .connecting: return .connecting
            case .paused: return .paused
            // No icon after Stop, or when the stream failed to play.
            case .stopped, .failed: return nil
            }
        }

        private func configure(_ cell: StationNameCellView, for station: Station) {
            let starred = parent?.showsFavoriteStars == true && model?.isFavorite(station) == true
            let pinned = parent?.allowsDelete == true && station.pinned == true
            cell.configure(name: station.name, mark: playMark(for: station), isFavorite: starred, isPinned: pinned)
        }

        /// Brings the Name cells on screen up to date, without reloading the
        /// table. A reload would replace the cells and could make VoiceOver
        /// lose its place; this only changes what has changed. Rows scrolled
        /// out of sight get set up fresh when they come back (see viewFor).
        func refreshNameCells() {
            guard let table else { return }
            let column = table.column(withIdentifier: Column.name.identifier)
            guard column >= 0 else { return }
            // The rows currently visible in the scroll view.
            let visible = table.rows(in: table.visibleRect)
            for row in visible.location..<(visible.location + visible.length) {
                guard let station = station(at: row),
                      let cell = table.view(atColumn: column, row: row, makeIfNecessary: false)
                        as? StationNameCellView else { continue }
                configure(cell, for: station)
            }
        }

        // The table asks: what kind of row view? Ours (StationRowView, below)
        // adds the VoiceOver behavior.
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = StationRowView()
            rowView.coordinator = self
            rowView.stationID = station(at: row)?.id
            return rowView
        }

        // The table says: the selection changed. Pass it on to SwiftUI,
        // unless this code made the change itself.
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncing, let table = notification.object as? NSTableView else { return }
            parent?.selection = station(at: table.selectedRow)?.id
        }

        // MARK: Context menu (right-click, Control-click, or VO-Shift-M)

        // Called just before the menu opens: fill it in for the row it opened on.
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table else { return }
            // The right-clicked row, or else the selected one (VO-Shift-M).
            let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
            guard station(at: row) != nil else { return }

            // Each item remembers its row in `tag`, for the functions below.
            let play = NSMenuItem(title: "Play", action: #selector(menuPlay(_:)), keyEquivalent: "")
            play.target = self
            play.tag = row
            menu.addItem(play)

            let favorite = NSMenuItem(title: favoriteActionTitle(row: row),
                                      action: #selector(menuToggleFavorite(_:)), keyEquivalent: "")
            favorite.target = self
            favorite.tag = row
            menu.addItem(favorite)

            // Only favorites can be renamed. (`allowsDelete` is on only for
            // the Favorites table.)
            if parent?.allowsDelete == true {
                let rename = NSMenuItem(title: "Rename…", action: #selector(menuRename(_:)), keyEquivalent: "")
                rename.target = self
                rename.tag = row
                menu.addItem(rename)

                if let title = pinActionTitle(row: row) {
                    let pin = NSMenuItem(title: title, action: #selector(menuTogglePin(_:)), keyEquivalent: "")
                    pin.target = self
                    pin.tag = row
                    menu.addItem(pin)
                }

                // Move Up and Move Down, the same as VoiceOver's actions:
                // left off the first favorite (up) and the last (down).
                if canMoveFavorite(row: row, by: -1) {
                    let up = NSMenuItem(title: "Move Up", action: #selector(menuMoveUp(_:)), keyEquivalent: "")
                    up.target = self
                    up.tag = row
                    menu.addItem(up)
                }
                if canMoveFavorite(row: row, by: 1) {
                    let down = NSMenuItem(title: "Move Down", action: #selector(menuMoveDown(_:)), keyEquivalent: "")
                    down.target = self
                    down.tag = row
                    menu.addItem(down)
                }
            }
        }

        @objc private func menuTogglePin(_ sender: NSMenuItem) { togglePin(row: sender.tag) }
        @objc private func menuMoveUp(_ sender: NSMenuItem) { moveFavorite(row: sender.tag, by: -1) }
        @objc private func menuMoveDown(_ sender: NSMenuItem) { moveFavorite(row: sender.tag, by: 1) }
        @objc private func menuPlay(_ sender: NSMenuItem) { play(row: sender.tag) }
        @objc private func menuToggleFavorite(_ sender: NSMenuItem) { toggleFavorite(row: sender.tag) }

        // Finds a station's current row. Rows shift as favorites are added or
        // moved, so rows remember their station, not their number.
        func row(for stationID: Station.ID?) -> Int? {
            guard let stationID else { return nil }
            return stations.firstIndex { $0.id == stationID }
        }
    }
}

// MARK: - AppKit subclasses

/// The table itself: a standard NSTableView with a few extra keys.
///
/// A "subclass" starts from an existing class and changes parts of it.
/// `override` marks a function that replaces the standard version;
/// `super.` calls the standard version, so everything else still works.
final class StationNSTableView: NSTableView {
    weak var coordinator: StationTable.Coordinator?

    // Called for every key pressed while the table has focus.
    override func keyDown(with event: NSEvent) {
        // Which of Command, Option, Control and Shift are held down.
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

        // Command-Delete (or Command-Forward Delete) removes a favorite. A plain
        // Delete does nothing, so a stray keypress can't remove a station.
        // Keys are identified by number: 51 is Delete, 117 is Forward Delete.
        if modifiers == .command, event.keyCode == 51 || event.keyCode == 117,
           selectedRow >= 0, let coordinator, coordinator.parent?.allowsDelete == true {
            coordinator.delete(row: selectedRow)
            return
        }

        // The keys below work only without modifiers and with a row selected.
        let plain = modifiers.isEmpty
        guard plain, selectedRow >= 0, let coordinator else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        // 36 is Return, 76 is Enter on the number keypad.
        case 36, 76:
            coordinator.play(row: selectedRow)
        // 49 is Space.
        case 49:
            coordinator.playOrPause(row: selectedRow)
        // Any other key (arrows, letters to jump by name) works as usual.
        default:
            super.keyDown(with: event)
        }
    }

    /// Called when an assistive app (VoiceOver) changes the selection.
    /// Keyboard and mouse selection don't come through here.
    override func setAccessibilitySelectedRows(_ rows: [any NSAccessibilityRow]) {
        // Which row was selected before VoiceOver's change, so the coordinator
        // can tell VO-Space (same row) from moving the cursor (a new row).
        let before = selectedRow
        super.setAccessibilitySelectedRows(rows)
        // Read the row through NSArray, never `rows.first` or `rows[0]`.
        //
        // Why: VoiceOver hands us an Objective-C array, and Swift only checks
        // each item's type when we take it out. Right after favorites are
        // reordered, VoiceOver can still be holding an old object that isn't a
        // proper table row. Swift's type check then fails, and that failure
        // crashes the app instead of returning nil. (Crash report frame:
        // `_ArrayBuffer._getElementSlowPath`.) Going through NSArray skips that
        // check, so `as? StationRowView` just gives nil for an odd object.
        let first = (rows as NSArray).firstObject
        if rows.count == 1, let rowView = first as? StationRowView, let row = rowView.currentRow {
            coordinator?.accessibilitySelected(row: row, wasSelected: row == before)
        } else if rows.count == 1, selectedRow >= 0 {
            coordinator?.accessibilitySelected(row: selectedRow, wasSelected: selectedRow == before)
        }
    }
}

/// A table row that VoiceOver can "press" (VO-Space) to play its station,
/// with Play, Add to / Remove from Favorites and (for favorites) Move Up
/// and Move Down as VoiceOver actions.
final class StationRowView: NSTableRowView {
    weak var coordinator: StationTable.Coordinator?
    // The station this row shows.
    var stationID: Station.ID?

    var currentRow: Int? { coordinator?.row(for: stationID) }
    private var row: Int? { currentRow }

    /// VoiceOver selecting this row: VO-Space plays it, but moving the
    /// VoiceOver cursor onto it only selects it (see accessibilitySelected).
    override func setAccessibilitySelected(_ selected: Bool) {
        // Whether this row was already selected, checked before the change.
        let wasSelected = isSelected
        super.setAccessibilitySelected(selected)
        if selected, let row { coordinator?.accessibilitySelected(row: row, wasSelected: wasSelected) }
    }

    // VoiceOver's "press" action, which VO-Shift-Space (a mouse click) also reaches.
    override func accessibilityPerformPress() -> Bool {
        guard let row else { return false }
        coordinator?.play(row: row)
        return true
    }

    // VO-Shift-M: select this row and open the context menu beside it.
    override func accessibilityPerformShowMenu() -> Bool {
        guard let row, let table = superview as? NSTableView, let menu = table.menu else { return false }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        menu.popUp(positioning: nil, at: NSPoint(x: 20, y: bounds.midY), in: self)
        return true
    }

    // The actions VoiceOver lists for this row (VO-Command-Space).
    // Favorites also get Move Up and Move Down, matching the iPhone's
    // Actions rotor: Move Up is left off the first favorite and Move Down
    // off the last, since they can't go any further.
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard let row, let coordinator else { return nil }
        var actions = [
            NSAccessibilityCustomAction(name: "Play") { [weak coordinator] in
                coordinator?.play(row: row)
                return true
            },
            NSAccessibilityCustomAction(name: coordinator.favoriteActionTitle(row: row)) { [weak coordinator] in
                coordinator?.toggleFavorite(row: row)
                return true
            },
        ]
        if let title = coordinator.pinActionTitle(row: row) {
            actions.append(NSAccessibilityCustomAction(name: title) { [weak coordinator] in
                coordinator?.togglePin(row: row)
                return true
            })
        }
        if coordinator.canMoveFavorite(row: row, by: -1) {
            actions.append(NSAccessibilityCustomAction(name: "Move Up") { [weak coordinator] in
                coordinator?.moveFavorite(row: row, by: -1)
                return true
            })
        }
        if coordinator.canMoveFavorite(row: row, by: 1) {
            actions.append(NSAccessibilityCustomAction(name: "Move Down") { [weak coordinator] in
                coordinator?.moveFavorite(row: row, by: 1)
                return true
            })
        }
        return actions
    }
}

/// The Name cell: the station's name, with a speaker icon in front of the
/// playing station and, in Search results, a star on stations that are
/// already favorites.
///
/// VoiceOver doesn't read the icons themselves (an icon would be spoken as
/// "image"). Instead the same information is added to the end of the name it
/// reads, such as "WOTR, favorite, now playing", so VoiceOver users get what
/// the icons show.
final class StationNameCellView: NSTableCellView {
    /// What the speaker icon shows, and the words VoiceOver adds for it.
    enum PlayMark {
        case playing, connecting, paused

        // The SF Symbols name (Apple's built-in icon set) for each.
        var symbol: String {
            switch self {
            case .playing: return "speaker.wave.2.fill"
            case .connecting: return "speaker.fill"
            case .paused: return "pause.fill"
            }
        }

        var spoken: String {
            switch self {
            case .playing: return "now playing"
            case .connecting: return "connecting"
            case .paused: return "paused"
            }
        }
    }

    private let speaker = DecorativeImageView()
    private let star = DecorativeImageView()
    // What the cell shows now, so configure can skip work when nothing changed.
    // (Setting the same text again could make VoiceOver re-read the row.)
    private var shown: (name: String, mark: PlayMark?, isFavorite: Bool, isPinned: Bool)?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        // Small icons, sized to sit beside the text.
        let size = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        speaker.symbolConfiguration = size
        speaker.contentTintColor = .controlAccentColor
        star.symbolConfiguration = size
        star.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil)
        star.contentTintColor = .systemYellow
        star.toolTip = "Favorite"
        for icon in [speaker, star] {
            // Hidden from VoiceOver; the words are in the name instead (see above).
            icon.setAccessibilityElement(false)
            // Icons keep their size; the name gets the rest of the width.
            icon.setContentHuggingPriority(.required, for: .horizontal)
            icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        // Text too long for the column ends in "…". SpokenTextField (below)
        // lets VoiceOver read more than the name on screen.
        let field = SpokenTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField = field

        // A stack view lines the pieces up left to right. A hidden icon takes
        // no room, so the name moves over when there's no icon.
        let stack = NSStackView(views: [speaker, star, field])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // Fill the cell's width (2 points in from each side), centered vertically.
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    // AppKit sets this to `.emphasized` while the row is selected (the blue
    // highlight). The blue speaker icon would vanish against it, so it turns
    // white like the text does, and back to blue when the row is deselected.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            speaker.contentTintColor = backgroundStyle == .emphasized
                ? .alternateSelectedControlTextColor : .controlAccentColor
        }
    }

    // Required by AppKit for views loaded from interface files, which this app doesn't use.
    required init?(coder: NSCoder) { fatalError("not used") }

    // VO-Space can land on the cell itself (it did in Favorites); pass it to
    // the text, which passes it to the row. See SpokenTextField.
    override func accessibilityPerformPress() -> Bool {
        (textField as? SpokenTextField)?.accessibilityPerformPress() ?? false
    }

    // What VoiceOver finds inside this cell: only the name. Without this,
    // VoiceOver still found the speaker icon and read Apple's built-in name
    // for it, "volume high, image", whatever the volume. The name already
    // ends with "now playing" (or "favorite"), so the icon adds nothing.
    override func accessibilityChildren() -> [Any]? {
        textField.map { [$0] }
    }

    func configure(name: String, mark: PlayMark?, isFavorite: Bool, isPinned: Bool = false) {
        if let shown, shown.name == name, shown.mark == mark, shown.isFavorite == isFavorite,
           shown.isPinned == isPinned { return }
        shown = (name, mark, isFavorite, isPinned)

        speaker.isHidden = mark == nil
        if let mark {
            speaker.image = NSImage(systemSymbolName: mark.symbol, accessibilityDescription: nil)
            speaker.toolTip = mark.spoken.prefix(1).uppercased() + mark.spoken.dropFirst()
        }
        star.isHidden = !isFavorite

        guard let field = textField else { return }
        field.stringValue = name
        // Hovering the pointer shows the full name.
        field.toolTip = name.isEmpty ? nil : name
        // The playing station's name is bold, so it stands out at a glance.
        field.font = mark == nil ? .systemFont(ofSize: NSFont.systemFontSize)
                                 : .boldSystemFont(ofSize: NSFont.systemFontSize)
        // What VoiceOver reads: the name, then what the icons show.
        var spoken = [name]
        if isFavorite { spoken.append("favorite") }
        // Pinned favorites also have a button in the Pinned row above.
        if isPinned { spoken.append("pinned") }
        if let mark { spoken.append(mark.spoken) }
        (field as? SpokenTextField)?.spokenText = spoken.joined(separator: ", ")
    }
}

/// An icon that's only for the eye. VoiceOver skips it.
///
/// `setAccessibilityElement(false)` alone wasn't enough: an image view's
/// accessibility comes partly from its inner "cell", which still told
/// VoiceOver about the picture. Overriding these two answers hides it
/// whichever way VoiceOver asks.
final class DecorativeImageView: NSImageView {
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { [] }
}

/// A text label that VoiceOver reads differently from what it shows: the
/// station's name on screen, but "WOTR, favorite, now playing" for VoiceOver.
///
/// Why a subclass: calling `setAccessibilityValue` on a plain label didn't
/// stick, because the label works out its value from its text each time
/// VoiceOver asks. (The "now playing" VoiceOver used to read came from the
/// speaker icon's hover tip; hiding the icon hid the words too.) Answering
/// the question ourselves, here, always gives VoiceOver the full text.
final class SpokenTextField: NSTextField {
    /// What VoiceOver reads. Nil means just the text on screen.
    var spokenText: String?

    override func accessibilityValue() -> String? {
        spokenText ?? super.accessibilityValue()
    }

    // VO-Space on a table row. On macOS 27, VoiceOver sends VO-Space to the
    // text in the cell, not to the row or the table: a log showed no select
    // or press reaching either. So the text passes the press on to its row,
    // which plays the station. (Found 2026-11-12.)
    override func accessibilityPerformPress() -> Bool {
        var view = superview
        while let current = view, !(current is StationRowView) { view = current.superview }
        if let rowView = view as? StationRowView { return rowView.accessibilityPerformPress() }
        return super.accessibilityPerformPress()
    }

    // Deliberately NOT overriding accessibilityRole() here.
    //
    // Apple's accessibility audit reports these labels as "unknown role", and
    // answering `.staticText` silenced it. But it also broke VO-Space on the
    // table: VoiceOver has nothing to "press" on plain static text, so the
    // keypress stopped reaching the row and never played the station. (Added
    // and removed 2026-11-12; VO-Space working matters far more than a clean
    // audit, so the "unknown role" result is listed as a known one in README.)
}

/// A plain table cell (Country, Format, Tags) that passes VO-Space on to its
/// row, the same as the Name column's cell does. On macOS 27 VoiceOver sends
/// VO-Space to the cell or its text rather than to the row, so without this
/// VO-Space did nothing in the table. (Found with logging, 2026-11-12.)
final class PressableCellView: NSTableCellView {
    override func accessibilityPerformPress() -> Bool {
        (textField as? SpokenTextField)?.accessibilityPerformPress() ?? false
    }
}
