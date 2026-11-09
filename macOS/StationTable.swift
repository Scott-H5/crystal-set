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

        /// VoiceOver's VO-Space selects a row through the accessibility API
        /// rather than the keyboard or mouse; treat that as "play this station".
        /// Both the table and the row may report the same selection, so ignore
        /// a repeat for the same row within a second.
        func accessibilitySelected(row: Int) {
            let now = Date()
            if row == lastAccessibilityRow, now.timeIntervalSince(lastAccessibilityTime) < 1 { return }
            lastAccessibilityRow = row
            lastAccessibilityTime = now
            play(row: row)
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

            // Reuse a cell that has scrolled out of sight if there is one;
            // otherwise make a new one.
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: tableColumn.identifier, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = tableColumn.identifier
                // A plain text label. Text too long for the column ends in "…".
                let field = NSTextField(labelWithString: "")
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
            // Hovering the pointer shows the full text.
            cell.textField?.toolTip = text.isEmpty ? nil : text
            return cell
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
            }
        }

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
        super.setAccessibilitySelectedRows(rows)
        if rows.count == 1, let rowView = rows.first as? StationRowView, let row = rowView.currentRow {
            coordinator?.accessibilitySelected(row: row)
        } else if rows.count == 1, selectedRow >= 0 {
            coordinator?.accessibilitySelected(row: selectedRow)
        }
    }
}

/// A table row that VoiceOver can "press" (VO-Space) to play its station,
/// with Play and Add to / Remove from Favorites as VoiceOver actions.
final class StationRowView: NSTableRowView {
    weak var coordinator: StationTable.Coordinator?
    // The station this row shows.
    var stationID: Station.ID?

    var currentRow: Int? { coordinator?.row(for: stationID) }
    private var row: Int? { currentRow }

    /// VoiceOver selecting this row (VO-Space) plays it.
    override func setAccessibilitySelected(_ selected: Bool) {
        super.setAccessibilitySelected(selected)
        if selected, let row { coordinator?.accessibilitySelected(row: row) }
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
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard let row, let coordinator else { return nil }
        return [
            NSAccessibilityCustomAction(name: "Play") { [weak coordinator] in
                coordinator?.play(row: row)
                return true
            },
            NSAccessibilityCustomAction(name: coordinator.favoriteActionTitle(row: row)) { [weak coordinator] in
                coordinator?.toggleFavorite(row: row)
                return true
            },
        ]
    }
}
