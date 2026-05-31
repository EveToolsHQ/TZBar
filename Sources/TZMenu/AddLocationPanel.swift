import AppKit
import MapKit

final class AddLocationPanelController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, MKLocalSearchCompleterDelegate, NSSearchFieldDelegate {
    private let completer = MKLocalSearchCompleter()
    private var completions: [MKLocalSearchCompletion] = []
    private var onAdded: (() -> Void)?

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "Search for a place…")

    convenience init(onAdded: @escaping () -> Void) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Add Location"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false

        self.init(window: panel)
        self.onAdded = onAdded
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        searchField.placeholderString = "Bali, Dubai, Montreal…"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.focusRingType = .none

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(tableViewDoubleClicked)
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("place")))
        tableView.rowHeight = 22

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(searchField)
        contentView.addSubview(statusLabel)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            statusLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    func showPanel() {
        guard let window else { return }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(searchField)
    }

    func controlTextDidChange(_ obj: Notification) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        completer.queryFragment = query
        if query.isEmpty {
            completions = []
            tableView.reloadData()
            statusLabel.stringValue = "Search for a place…"
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = completer.results
        tableView.reloadData()
        statusLabel.stringValue = completions.isEmpty ? "No results" : "Double-click to add"
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        statusLabel.stringValue = error.localizedDescription
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        completions.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let completion = completions[row]
        let text = "\(completion.title)\(completion.subtitle.isEmpty ? "" : " — \(completion.subtitle)")"
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func tableViewDoubleClicked() {
        let row = tableView.selectedRow
        guard row >= 0, row < completions.count else { return }
        addCompletion(completions[row])
    }

    private func addCompletion(_ completion: MKLocalSearchCompletion) {
        statusLabel.stringValue = "Resolving…"
        let displayName = completion.title + (completion.subtitle.isEmpty ? "" : ", \(completion.subtitle)")

        Task { @MainActor in
            do {
                let request = MKLocalSearch.Request(completion: completion)
                let response = try await MKLocalSearch(request: request).start()
                guard let item = response.mapItems.first,
                      let timeZone = item.timeZone
                else {
                    statusLabel.stringValue = "Could not resolve timezone"
                    return
                }

                let countryCode = countryCode(from: item)
                LocationStore.shared.add(
                    SavedLocation(
                        displayName: displayName,
                        timeZoneIdentifier: timeZone.identifier,
                        countryCode: countryCode
                    )
                )
                onAdded?()
                close()
            } catch {
                statusLabel.stringValue = error.localizedDescription
            }
        }
    }

    private func countryCode(from item: MKMapItem) -> String? {
        if let code = item.placemark.isoCountryCode, !code.isEmpty {
            return code
        }
        if let code = item.placemark.countryCode, !code.isEmpty {
            return code
        }
        return nil
    }
}
