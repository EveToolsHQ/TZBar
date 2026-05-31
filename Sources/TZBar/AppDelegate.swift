import AppKit
import ServiceManagement

private final class LocationMenuTag: NSObject {
    let location: SavedLocation

    init(location: SavedLocation) {
        self.location = location
    }
}

private enum LocationMenuMetrics {
    static let dayPhaseSymbolSize: CGFloat = 13
    static let menuTrailingInset: CGFloat = 18
    static let timeToDayPhaseSpacing: CGFloat = 6
}

private final class LocationMenuItemView: NSView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let dayPhaseView = NSImageView()

    init(
        flag: String,
        name: String,
        time: String,
        dayPhase: DayPhase,
        showsDayPhase: Bool,
        width: CGFloat
    ) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        autoresizingMask = [.width]

        nameLabel.stringValue = "\(flag)  \(name)"
        nameLabel.font = NSFont.menuFont(ofSize: 0)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.stringValue = time
        timeLabel.font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.menuFont(ofSize: 0).pointSize,
            weight: .regular
        )
        timeLabel.alignment = .right
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        if showsDayPhase,
           let image = NSImage(
               systemSymbolName: dayPhase.symbolName,
               accessibilityDescription: dayPhase.accessibilityLabel
           ) {
            image.isTemplate = true
            let pointSize = NSFont.menuFont(ofSize: 0).pointSize
            let config = NSImage.SymbolConfiguration(
                pointSize: pointSize * 0.9,
                weight: .medium
            )
            dayPhaseView.image = image.withSymbolConfiguration(config) ?? image
        }
        dayPhaseView.imageScaling = .scaleProportionallyDown
        dayPhaseView.translatesAutoresizingMaskIntoConstraints = false
        dayPhaseView.isHidden = !showsDayPhase

        addSubview(nameLabel)
        addSubview(timeLabel)
        addSubview(dayPhaseView)

        let symbolSize = LocationMenuMetrics.dayPhaseSymbolSize
        var constraints: [NSLayoutConstraint] = [
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -12),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        if showsDayPhase {
            constraints += [
                dayPhaseView.trailingAnchor.constraint(
                    equalTo: trailingAnchor,
                    constant: -LocationMenuMetrics.menuTrailingInset
                ),
                dayPhaseView.centerYAnchor.constraint(equalTo: centerYAnchor),
                dayPhaseView.widthAnchor.constraint(equalToConstant: symbolSize),
                dayPhaseView.heightAnchor.constraint(equalToConstant: symbolSize),
                timeLabel.trailingAnchor.constraint(
                    equalTo: dayPhaseView.leadingAnchor,
                    constant: -LocationMenuMetrics.timeToDayPhaseSpacing
                ),
            ]
        } else {
            constraints.append(
                timeLabel.trailingAnchor.constraint(
                    equalTo: trailingAnchor,
                    constant: -LocationMenuMetrics.menuTrailingInset
                )
            )
        }
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(time: String, dayPhase: DayPhase) {
        timeLabel.stringValue = time
        if !dayPhaseView.isHidden,
           let image = NSImage(
               systemSymbolName: dayPhase.symbolName,
               accessibilityDescription: dayPhase.accessibilityLabel
           ) {
            image.isTemplate = true
            let pointSize = NSFont.menuFont(ofSize: 0).pointSize
            let config = NSImage.SymbolConfiguration(pointSize: pointSize * 0.9, weight: .medium)
            dayPhaseView.image = image.withSymbolConfiguration(config) ?? image
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if let menuItem = enclosingMenuItem, menuItem.isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            dirtyRect.fill()
            nameLabel.textColor = .selectedMenuItemTextColor
            timeLabel.textColor = .selectedMenuItemTextColor
            dayPhaseView.contentTintColor = .selectedMenuItemTextColor
        } else {
            nameLabel.textColor = .labelColor
            timeLabel.textColor = .secondaryLabelColor
            dayPhaseView.contentTintColor = .secondaryLabelColor
        }
        super.draw(dirtyRect)
    }
}

private final class TimeScrubberMenuItemView: NSView {
    private static let timeLabelWidth: CGFloat = 44

    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1439, target: nil, action: nil)
    private let timeLabel = NSTextField(labelWithString: "")
    private let onScrub: (Int) -> Void
    private let referenceTimeZone: TimeZone

    init(width: CGFloat, minutes: Int, referenceTimeZone: TimeZone, onScrub: @escaping (Int) -> Void) {
        self.onScrub = onScrub
        self.referenceTimeZone = referenceTimeZone
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        autoresizingMask = [.width]

        timeLabel.font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.menuFont(ofSize: 0).pointSize,
            weight: .regular
        )
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.alignment = .right
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        slider.isContinuous = true
        slider.controlSize = .mini
        slider.doubleValue = Double(minutes)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.target = self
        slider.action = #selector(sliderChanged)

        addSubview(timeLabel)
        addSubview(slider)

        NSLayoutConstraint.activate([
            timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeLabel.widthAnchor.constraint(equalToConstant: Self.timeLabelWidth),
            slider.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 8),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateTimeLabel(minutes: minutes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    @objc private func sliderChanged() {
        let minutes = Int(slider.doubleValue.rounded())
        updateTimeLabel(minutes: minutes)
        onScrub(minutes)
    }

    private func updateTimeLabel(minutes: Int) {
        let date = date(atMinutesSinceMidnight: minutes, in: referenceTimeZone)
        timeLabel.stringValue = formattedTime(in: referenceTimeZone.identifier, at: date)
    }
}

private final class SettingsMenuItemView: NSView {
    private static let iconSize: CGFloat = 13

    private let gearView = NSImageView()

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        autoresizingMask = [.width]

        if let image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings") {
            image.isTemplate = true
            let pointSize = NSFont.menuFont(ofSize: 0).pointSize
            let config = NSImage.SymbolConfiguration(pointSize: pointSize * 0.9, weight: .medium)
            gearView.image = image.withSymbolConfiguration(config) ?? image
        }
        gearView.imageScaling = .scaleProportionallyDown
        gearView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gearView)

        NSLayoutConstraint.activate([
            gearView.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -LocationMenuMetrics.menuTrailingInset
            ),
            gearView.centerYAnchor.constraint(equalTo: centerYAnchor),
            gearView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            gearView.heightAnchor.constraint(equalToConstant: Self.iconSize),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        if let menuItem = enclosingMenuItem, menuItem.isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            dirtyRect.fill()
            gearView.contentTintColor = .selectedMenuItemTextColor
        } else {
            gearView.contentTintColor = .secondaryLabelColor
        }
        super.draw(dirtyRect)
    }
}

private struct LocationMenuEntry {
    let location: SavedLocation
    let view: LocationMenuItemView
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var globeStatusItem: NSStatusItem?
    private var pinnedStatusItems: [String: NSStatusItem] = [:]
    private let menu = NSMenu()
    private var addPopover: AddLocationPopoverController?
    private var editPopover: EditLocationPopoverController?
    private let minuteTimer = MinuteBoundaryTimer()
    private var scrubberActive = false
    private var scrubMinutes: Int?
    private var showScrubberOnNextOpen = false
    private var locationMenuEntries: [LocationMenuEntry] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        syncStatusBar()
        rebuildMenu()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClockOrActivationChange),
            name: NSNotification.Name.NSSystemClockDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClockOrActivationChange),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "q"
            else { return event }
            NSApp.terminate(nil)
            return nil
        }
    }

    @objc private func handleClockOrActivationChange() {
        updatePinnedStatusItemTitles()
        if !LocationStore.shared.pinnedLocations().isEmpty {
            minuteTimer.reschedule()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if showScrubberOnNextOpen {
            showScrubberOnNextOpen = false
            scrubberActive = true
        } else if !scrubberActive {
            scrubMinutes = nil
            locationMenuEntries.removeAll()
        }
        rebuildMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        if showScrubberOnNextOpen { return }
        scrubberActive = false
        scrubMinutes = nil
        locationMenuEntries.removeAll()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        locationMenuEntries.removeAll()
        let displayDate = menuDisplayDate()
        let locations = LocationStore.shared.sortedByOffset()
        let menuWidth = max(locationMenuWidth(for: locations, at: displayDate), scrubberActive ? 260 : 0)

        for location in locations {
            let flag = location.emojiText
            let name = location.labelText
            let time = formattedTime(in: location.timeZoneIdentifier, at: displayDate)
            let phase = dayPhase(in: location.timeZoneIdentifier, at: displayDate)
            let showsDayPhase = AppPreferences.showDayPhaseIcons
            let item = NSMenuItem(title: "\(flag)  \(name)  \(time)", action: nil, keyEquivalent: "")
            let rowView = LocationMenuItemView(
                flag: flag,
                name: name,
                time: time,
                dayPhase: phase,
                showsDayPhase: showsDayPhase,
                width: menuWidth
            )
            item.view = rowView
            if scrubberActive {
                locationMenuEntries.append(LocationMenuEntry(location: location, view: rowView))
            }

            let locationMenu = NSMenu()
            let pinItem = NSMenuItem(
                title: "Show in Menu Bar",
                action: #selector(togglePinLocation(_:)),
                keyEquivalent: ""
            )
            pinItem.target = self
            pinItem.representedObject = LocationMenuTag(location: location)
            pinItem.state = LocationStore.shared.isPinned(location) ? .on : .off
            locationMenu.addItem(pinItem)

            let editItem = NSMenuItem(
                title: "Edit…",
                action: #selector(showEditPopover(_:)),
                keyEquivalent: ""
            )
            editItem.target = self
            editItem.representedObject = LocationMenuTag(location: location)
            locationMenu.addItem(editItem)

            locationMenu.addItem(.separator())

            let deleteItem = NSMenuItem(
                title: "Delete",
                action: #selector(deleteLocation(_:)),
                keyEquivalent: ""
            )
            deleteItem.target = self
            deleteItem.representedObject = LocationMenuTag(location: location)
            locationMenu.addItem(deleteItem)
            item.submenu = locationMenu

            menu.addItem(item)
        }

        if locations.isEmpty {
            menu.addItem(makeAddMenuItem())
            menu.addItem(.separator())
        } else {
            menu.addItem(.separator())
        }

        if scrubberActive {
            let scrubberItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            let minutes = scrubMinutes ?? minutesSinceMidnight(in: TimeZone.current)
            scrubberItem.view = TimeScrubberMenuItemView(
                width: menuWidth,
                minutes: minutes,
                referenceTimeZone: TimeZone.current,
                onScrub: { [weak self] newMinutes in
                    self?.scrubMinutes = newMinutes
                    self?.updateScrubbedLocationTimes()
                }
            )
            menu.addItem(scrubberItem)
        }

        let settingsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        settingsItem.view = SettingsMenuItemView(width: menuWidth)

        let settingsMenu = NSMenu()
        if !locations.isEmpty {
            settingsMenu.addItem(makeAddMenuItem())
        }

        let dayPhaseIconsItem = NSMenuItem(
            title: "Phase Icons",
            action: #selector(toggleDayPhaseIcons(_:)),
            keyEquivalent: ""
        )
        dayPhaseIconsItem.target = self
        dayPhaseIconsItem.state = AppPreferences.showDayPhaseIcons ? .on : .off
        settingsMenu.addItem(dayPhaseIconsItem)

        if !locations.isEmpty {
            let timeScrubberItem = NSMenuItem(
                title: "Time Scrubber",
                action: #selector(enableTimeScrubber(_:)),
                keyEquivalent: ""
            )
            timeScrubberItem.target = self
            settingsMenu.addItem(timeScrubberItem)
        }

        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = launchAtLoginEnabled ? .on : .off
        settingsMenu.addItem(launchAtLoginItem)

        settingsMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        settingsMenu.addItem(quitItem)

        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)
    }

    private func makeAddMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Add…", action: #selector(showAddPopover), keyEquivalent: "")
        item.target = self
        return item
    }

    private func menuDisplayDate() -> Date {
        guard scrubberActive, let minutes = scrubMinutes else { return Date() }
        return date(atMinutesSinceMidnight: minutes, in: TimeZone.current)
    }

    private func updateScrubbedLocationTimes() {
        let displayDate = menuDisplayDate()
        for entry in locationMenuEntries {
            let time = formattedTime(in: entry.location.timeZoneIdentifier, at: displayDate)
            let phase = dayPhase(in: entry.location.timeZoneIdentifier, at: displayDate)
            entry.view.update(time: time, dayPhase: phase)
        }
    }

    @objc private func enableTimeScrubber(_ sender: NSMenuItem) {
        scrubMinutes = minutesSinceMidnight(in: TimeZone.current)
        showScrubberOnNextOpen = true
        // Let settings click close menu, then reopen via same path as normal click.
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, let button = self.menuAnchorButton else {
                    self?.showScrubberOnNextOpen = false
                    return
                }
                button.performClick(nil)
            }
        }
    }

    private func locationMenuWidth(for locations: [SavedLocation], at date: Date) -> CGFloat {
        let nameFont = NSFont.menuFont(ofSize: 0)
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: nameFont.pointSize, weight: .regular)
        var width: CGFloat = 200

        for location in locations {
            let name = "\(location.emojiText)  \(location.labelText)"
            let time = formattedTime(in: location.timeZoneIdentifier, at: date)
            let nameWidth = (name as NSString).size(withAttributes: [.font: nameFont]).width
            let timeWidth = (time as NSString).size(withAttributes: [.font: timeFont]).width
            let trailingWidth: CGFloat
            if AppPreferences.showDayPhaseIcons {
                trailingWidth = LocationMenuMetrics.dayPhaseSymbolSize
                    + LocationMenuMetrics.timeToDayPhaseSpacing
                    + LocationMenuMetrics.menuTrailingInset
            } else {
                trailingWidth = LocationMenuMetrics.menuTrailingInset
            }
            width = max(width, nameWidth + timeWidth + trailingWidth + 34)
        }

        return ceil(width)
    }

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleDayPhaseIcons(_ sender: NSMenuItem) {
        AppPreferences.showDayPhaseIcons = sender.state != .on
        sender.state = AppPreferences.showDayPhaseIcons ? .on : .off
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let enable = sender.state != .on
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            sender.state = launchAtLoginEnabled ? .on : .off
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not update Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func togglePinLocation(_ sender: NSMenuItem) {
        guard let tag = sender.representedObject as? LocationMenuTag else { return }
        LocationStore.shared.setPinned(tag.location, pinned: sender.state != .on)
        syncStatusBar()
        rebuildMenu()
    }

    @objc private func deleteLocation(_ sender: NSMenuItem) {
        guard let tag = sender.representedObject as? LocationMenuTag else { return }
        LocationStore.shared.remove(tag.location)
        syncStatusBar()
        rebuildMenu()
    }

    @objc private func showEditPopover(_ sender: NSMenuItem) {
        guard let tag = sender.representedObject as? LocationMenuTag,
              let button = menuAnchorButton
        else { return }
        editPopover = EditLocationPopoverController(location: tag.location) { [weak self] in
            self?.syncStatusBar()
            self?.rebuildMenu()
        }
        DispatchQueue.main.async { [weak self] in
            self?.editPopover?.show(relativeTo: button.bounds, of: button)
        }
    }

    @objc private func showAddPopover() {
        guard let button = menuAnchorButton else { return }
        if addPopover == nil {
            addPopover = AddLocationPopoverController { [weak self] in
                self?.syncStatusBar()
                self?.rebuildMenu()
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.addPopover?.toggle(relativeTo: button.bounds, of: button)
        }
    }

    private var menuAnchorButton: NSStatusBarButton? {
        if let button = globeStatusItem?.button { return button }
        for location in LocationStore.shared.pinnedLocations() {
            if let button = pinnedStatusItems[location.pinKey]?.button {
                return button
            }
        }
        return nil
    }

    private func syncStatusBar() {
        let pinned = LocationStore.shared.pinnedLocations()
        let now = Date()

        if pinned.isEmpty {
            minuteTimer.stop()
            removePinnedStatusItems()
            ensureGlobeStatusItem()
        } else {
            removeGlobeStatusItem()
            let activeKeys = Set(pinned.map(\.pinKey))
            for key in pinnedStatusItems.keys where !activeKeys.contains(key) {
                if let item = pinnedStatusItems.removeValue(forKey: key) {
                    NSStatusBar.system.removeStatusItem(item)
                }
            }
            for location in pinned {
                let key = location.pinKey
                let item = pinnedStatusItems[key] ?? makePinnedStatusItem()
                pinnedStatusItems[key] = item
                applyPinnedAppearance(to: item, location: location, at: now)
            }
            refreshMinuteTimer()
        }

        attachMenuToAllStatusItems()
    }

    private func attachMenuToAllStatusItems() {
        globeStatusItem?.menu = menu
        for item in pinnedStatusItems.values {
            item.menu = menu
        }
    }

    private func refreshMinuteTimer() {
        guard !LocationStore.shared.pinnedLocations().isEmpty else {
            minuteTimer.stop()
            return
        }
        updatePinnedStatusItemTitles()
        minuteTimer.start { [weak self] in
            self?.updatePinnedStatusItemTitles()
        }
    }

    private func updatePinnedStatusItemTitles() {
        let now = Date()
        for location in LocationStore.shared.pinnedLocations() {
            guard let item = pinnedStatusItems[location.pinKey] else { continue }
            applyPinnedAppearance(to: item, location: location, at: now)
        }
    }

    private func makePinnedStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = menu
        return item
    }

    private func applyPinnedAppearance(to item: NSStatusItem, location: SavedLocation, at date: Date) {
        guard let button = item.button else { return }
        let flag = location.emojiText
        let time = formattedTime(in: location.timeZoneIdentifier, at: date)
        let name = location.labelText
        button.image = nil
        button.title = "\(flag) \(time)"
        button.font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
        button.toolTip = name
        button.setAccessibilityLabel("\(name), \(time)")
    }

    private func ensureGlobeStatusItem() {
        if globeStatusItem != nil { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        globeStatusItem = item
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "globe", accessibilityDescription: "TZBar") {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                button.image = image
                button.title = ""
            } else {
                button.image = nil
                button.title = "🌐"
            }
        }
        item.menu = menu
    }

    private func removeGlobeStatusItem() {
        guard let item = globeStatusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        globeStatusItem = nil
    }

    private func removePinnedStatusItems() {
        for item in pinnedStatusItems.values {
            NSStatusBar.system.removeStatusItem(item)
        }
        pinnedStatusItems.removeAll()
    }
}
