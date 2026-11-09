import AppKit
import SwiftUI

// MARK: - Station table

/// A standard AppKit table of stations, wrapped for SwiftUI.
///
/// AppKit is used here (instead of SwiftUI's Table) so the table can tell when
/// VoiceOver selects a row (VO-Space) and play that station. The table also
/// plays on Return, Space, or double-click; Delete removes a favorite; and it
/// has a context menu (VO-Shift-M) and VoiceOver actions (VO-Command-Space)
/// with Play and Add to / Remove from Favorites.
struct StationTable: NSViewRepresentable {
    @EnvironmentObject private var model: AppModel
    let stations: [Station]
    @Binding var selection: Station.ID?
    let title: String
    /// Delete and Forward Delete remove the selected station (Favorites only).
    var allowsDelete = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        coordinator.parent = self

        let table = StationNSTableView()
        table.coordinator = coordinator
        table.dataSource = coordinator
        table.delegate = coordinator
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.style = .inset
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.target = coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.setAccessibilityLabel(title)

        for column in Column.allCases {
            let tableColumn = NSTableColumn(identifier: column.identifier)
            tableColumn.title = column.rawValue
            tableColumn.minWidth = column.minWidth
            tableColumn.width = column.width
            table.addTableColumn(tableColumn)
        }

        let menu = NSMenu()
        menu.delegate = coordinator
        table.menu = menu

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        coordinator.table = table
        coordinator.stations = stations
        coordinator.syncSelection()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.table?.setAccessibilityLabel(title)
        if coordinator.stations != stations {
            coordinator.stations = stations
            coordinator.reload()
        }
        coordinator.syncSelection()
    }

    // MARK: Columns

    enum Column: String, CaseIterable {
        case name = "Name"
        case country = "Country"
        case format = "Format"
        case tags = "Tags"

        var identifier: NSUserInterfaceItemIdentifier { .init(rawValue) }

        var minWidth: CGFloat {
            switch self {
            case .name: return 140
            case .country, .format, .tags: return 70
            }
        }

        var width: CGFloat {
            switch self {
            case .name: return 260
            case .country: return 150
            case .format: return 100
            case .tags: return 200
            }
        }

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

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: StationTable?
        weak var table: NSTableView?
        var stations: [Station] = []
        private var isSyncing = false

        private var model: AppModel? { parent?.model }

        func station(at row: Int) -> Station? {
            stations.indices.contains(row) ? stations[row] : nil
        }

        func reload() {
            isSyncing = true
            table?.reloadData()
            isSyncing = false
        }

        /// Makes the table's selection match the SwiftUI selection.
        func syncSelection() {
            guard let table else { return }
            let wanted = parent?.selection.flatMap { id in stations.firstIndex { $0.id == id } }
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

        // Actions

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
        private var lastAccessibilityRow = -1
        private var lastAccessibilityTime = Date.distantPast

        func delete(row: Int) {
            guard parent?.allowsDelete == true, let station = station(at: row) else { return }
            model?.removeFromFavorites(station)
        }

        func toggleFavorite(row: Int) {
            guard let station = station(at: row), let model else { return }
            if model.isFavorite(station) {
                model.removeFromFavorites(station)
            } else {
                model.addToFavorites(station)
            }
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

        @objc func doubleClicked(_ sender: NSTableView) {
            if sender.clickedRow >= 0 { play(row: sender.clickedRow) }
        }

        // Data source and delegate

        func numberOfRows(in tableView: NSTableView) -> Int { stations.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, let column = Column(rawValue: tableColumn.identifier.rawValue),
                  let station = station(at: row) else { return nil }

            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: tableColumn.identifier, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = tableColumn.identifier
                let field = NSTextField(labelWithString: "")
                field.lineBreakMode = .byTruncatingTail
                field.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(field)
                cell.textField = field
                NSLayoutConstraint.activate([
                    field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                    field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            let text = column.text(for: station)
            cell.textField?.stringValue = text
            cell.textField?.toolTip = text.isEmpty ? nil : text
            return cell
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = StationRowView()
            rowView.coordinator = self
            rowView.stationID = station(at: row)?.id
            return rowView
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncing, let table = notification.object as? NSTableView else { return }
            parent?.selection = station(at: table.selectedRow)?.id
        }

        // Context menu (right-click, Control-click, or VO-Shift-M)

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table else { return }
            let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
            guard station(at: row) != nil else { return }

            let play = NSMenuItem(title: "Play", action: #selector(menuPlay(_:)), keyEquivalent: "")
            play.target = self
            play.tag = row
            menu.addItem(play)

            let favorite = NSMenuItem(title: favoriteActionTitle(row: row),
                                      action: #selector(menuToggleFavorite(_:)), keyEquivalent: "")
            favorite.target = self
            favorite.tag = row
            menu.addItem(favorite)
        }

        @objc private func menuPlay(_ sender: NSMenuItem) { play(row: sender.tag) }
        @objc private func menuToggleFavorite(_ sender: NSMenuItem) { toggleFavorite(row: sender.tag) }

        func row(for stationID: Station.ID?) -> Int? {
            guard let stationID else { return nil }
            return stations.firstIndex { $0.id == stationID }
        }
    }
}

// MARK: - AppKit subclasses

/// Plays the selected station on Return or Enter.
final class StationNSTableView: NSTableView {
    weak var coordinator: StationTable.Coordinator?

    override func keyDown(with event: NSEvent) {
        let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        guard plain, selectedRow >= 0, let coordinator else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 36, 76:   // Return, keypad Enter
            coordinator.play(row: selectedRow)
        case 49:       // Space
            coordinator.playOrPause(row: selectedRow)
        case 51, 117:  // Delete, Forward Delete
            if coordinator.parent?.allowsDelete == true {
                coordinator.delete(row: selectedRow)
            } else {
                super.keyDown(with: event)
            }
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
    var stationID: Station.ID?

    var currentRow: Int? { coordinator?.row(for: stationID) }
    private var row: Int? { currentRow }

    /// VoiceOver selecting this row (VO-Space) plays it.
    override func setAccessibilitySelected(_ selected: Bool) {
        super.setAccessibilitySelected(selected)
        if selected, let row { coordinator?.accessibilitySelected(row: row) }
    }

    override func accessibilityPerformPress() -> Bool {
        guard let row else { return false }
        coordinator?.play(row: row)
        return true
    }

    override func accessibilityPerformShowMenu() -> Bool {
        guard let row, let table = superview as? NSTableView, let menu = table.menu else { return false }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        menu.popUp(positioning: nil, at: NSPoint(x: 20, y: bounds.midY), in: self)
        return true
    }

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
