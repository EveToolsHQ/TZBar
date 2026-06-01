import AppKit
import MapKit

final class AddLocationPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let viewController = AddLocationViewController()
    private var resignActiveObserver: NSObjectProtocol?

    init(onAdded: @escaping () -> Void) {
        super.init()
        popover.contentViewController = viewController
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        viewController.onAdded = { [weak self] in
            onAdded()
            self?.popover.performClose(nil)
        }
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            self?.closeIfShown()
        }
    }

    deinit {
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
        }
    }

    private func closeIfShown() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    func toggle(relativeTo positioningRect: NSRect, of positioningView: NSView) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        viewController.prepareForDisplay()
        popover.show(relativeTo: positioningRect, of: positioningView, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func popoverDidClose(_ notification: Notification) {
        viewController.prepareForDisplay()
    }
}

final class AddLocationViewController: NSViewController {
    private enum Layout {
        static let width: CGFloat = 280
        static let padding: CGFloat = 12
        static let spacing: CGFloat = 8
        static let emptyMinHeight: CGFloat = 56
        static let maxVisibleRows = 8
        static let rowHeight: CGFloat = 22
    }

    var onAdded: (() -> Void)?

    private let searchController = PlaceSearchController()
    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let bodyStack = NSStackView()
    private var resultsHeightConstraint: NSLayoutConstraint!

    init() {
        super.init(nibName: nil, bundle: nil)
        searchController.onResultsChanged = { [weak self] in
            self?.resultsDidChange()
        }
        searchController.onError = { [weak self] message in
            self?.showStatus(message)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.emptyMinHeight))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        searchField.placeholderString = "Search for a city or country"
        searchField.sendsSearchStringImmediately = true
        searchField.focusRingType = .default
        searchField.delegate = self

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        statusLabel.setContentHuggingPriority(.required, for: .vertical)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("place"))
        column.minWidth = Layout.width - Layout.padding * 2
        column.maxWidth = 10_000
        column.resizingMask = .autoresizingMask

        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.rowHeight = Layout.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(tableRowActivated)
        tableView.doubleAction = #selector(tableRowActivated)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        resultsHeightConstraint = scrollView.heightAnchor.constraint(equalToConstant: 0)

        bodyStack.orientation = .vertical
        bodyStack.alignment = .width
        bodyStack.spacing = Layout.spacing
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        bodyStack.addArrangedSubview(searchField)
        bodyStack.addArrangedSubview(statusLabel)
        bodyStack.addArrangedSubview(scrollView)
        statusLabel.isHidden = true

        view.addSubview(bodyStack)
        NSLayoutConstraint.activate([
            bodyStack.topAnchor.constraint(equalTo: view.topAnchor, constant: Layout.padding),
            bodyStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.padding),
            bodyStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.padding),
            bodyStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Layout.padding),
            searchField.widthAnchor.constraint(equalTo: bodyStack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: bodyStack.widthAnchor),
            resultsHeightConstraint,
        ])

        updatePreferredContentSize()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(searchField)
    }

    func prepareForDisplay() {
        loadViewIfNeeded()
        searchField.stringValue = ""
        searchController.reset()
        tableView.reloadData()
        clearStatus()
        updateResultsHeight()
        updatePreferredContentSize()
    }

    private func resultsDidChange() {
        tableView.reloadData()
        if searchController.completions.isEmpty {
            tableView.deselectAll(nil)
        } else {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
        refreshStatusForResults()
        updateResultsHeight()
        updatePreferredContentSize()
    }

    private func refreshStatusForResults() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearStatus()
            return
        }
        if searchController.completions.isEmpty {
            showStatus("No results")
        } else {
            clearStatus()
        }
    }

    private func clearStatus() {
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        updatePreferredContentSize()
    }

    private func showStatus(_ text: String) {
        statusLabel.stringValue = text
        statusLabel.isHidden = false
        updatePreferredContentSize()
    }

    private func updateResultsHeight() {
        let rows = searchController.completions.count
        let visibleRows = min(rows, Layout.maxVisibleRows)
        let tableHeight = rows == 0
            ? 0
            : CGFloat(visibleRows) * Layout.rowHeight + CGFloat(max(0, visibleRows - 1))
        resultsHeightConstraint.constant = tableHeight
        scrollView.isHidden = rows == 0
    }

    private func updatePreferredContentSize() {
        view.layoutSubtreeIfNeeded()
        let contentHeight = bodyStack.fittingSize.height + Layout.padding * 2
        let height = scrollView.isHidden
            ? max(contentHeight, Layout.emptyMinHeight)
            : contentHeight
        preferredContentSize = NSSize(width: Layout.width, height: height)
    }

    @objc private func tableRowActivated() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < searchController.completions.count else { return }
        resolveAndAdd(searchController.completions[row])
    }

    private func resolveAndAdd(_ completion: MKLocalSearchCompletion) {
        Task { @MainActor in
            do {
                let saved = try await searchController.resolve(completion)
                LocationStore.shared.add(saved)
                onAdded?()
            } catch {
                showStatus(error.localizedDescription)
            }
        }
    }

    private func moveSelection(by delta: Int) {
        let count = searchController.completions.count
        guard count > 0 else { return }
        let current = tableView.selectedRow < 0 ? 0 : tableView.selectedRow
        let next = min(count - 1, max(0, current + delta))
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    private func pickSelection() {
        let row = tableView.selectedRow
        guard row >= 0, row < searchController.completions.count else { return }
        resolveAndAdd(searchController.completions[row])
    }
}

extension AddLocationViewController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        searchController.search(query: query)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            pickSelection()
            return true
        default:
            return false
        }
    }
}

extension AddLocationViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        searchController.completions.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("PlaceResultCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
            let view = NSTableCellView()
            view.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: 13)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            view.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            return view
        }()

        let completion = searchController.completions[row]
        cell.textField?.stringValue = PlaceSearchController.displayLabel(for: completion)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        EmphasizedTableRowView()
    }
}

/// Popovers are non-key; without emphasis, AppKit draws gray selection with wrong text contrast.
private final class EmphasizedTableRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {}
    }
}

// MARK: - Search

private final class PlaceSearchController: NSObject, MKLocalSearchCompleterDelegate {
    private static let maxResults = 8
    private static let addressFilter = MKAddressFilter(including: [
        .country,
        .administrativeArea,
        .subAdministrativeArea,
        .locality,
    ])

    private let completer = MKLocalSearchCompleter()

    private(set) var completions: [MKLocalSearchCompletion] = []
    var onResultsChanged: (() -> Void)?
    var onError: ((String) -> Void)?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address]
        completer.pointOfInterestFilter = .excludingAll
        completer.addressFilter = Self.addressFilter
    }

    func reset() {
        completer.cancel()
        completions = []
    }

    func search(query: String) {
        guard !query.isEmpty else {
            reset()
            onResultsChanged?()
            return
        }
        completer.queryFragment = query
    }

    func resolve(_ completion: MKLocalSearchCompletion) async throws -> SavedLocation {
        let request = MKLocalSearch.Request(completion: completion)
        request.addressFilter = Self.addressFilter
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first,
              let timeZone = item.timeZone
        else {
            throw PlaceSearchError.unresolvedTimeZone
        }
        let locationName = Self.displayLabel(for: completion)
        let displayName = shortDisplayName(locationName)
        let countryCode = countryCode(from: item)
        return SavedLocation(
            displayName: displayName,
            timeZoneIdentifier: timeZone.identifier,
            emoji: flagEmoji(for: countryCode),
            locationName: locationName,
            countryCode: countryCode,
            mapItemID: item.identifier?.rawValue
        )
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = Array(completer.results.prefix(Self.maxResults))
        onResultsChanged?()
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        onError?(error.localizedDescription)
    }

    static func displayLabel(for completion: MKLocalSearchCompletion) -> String {
        if completion.subtitle.isEmpty {
            return completion.title
        }
        if completion.title.localizedCaseInsensitiveContains(completion.subtitle) {
            return completion.title
        }
        return "\(completion.title), \(completion.subtitle)"
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

private enum PlaceSearchError: LocalizedError {
    case unresolvedTimeZone

    var errorDescription: String? {
        switch self {
        case .unresolvedTimeZone:
            return "Could not resolve timezone"
        }
    }
}
