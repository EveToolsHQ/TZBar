import AppKit
import ServiceManagement

private final class LocationMenuTag: NSObject {
    let location: SavedLocation

    init(location: SavedLocation) {
        self.location = location
    }
}

private struct LocationMenuEntry {
    let location: SavedLocation
    let view: MenuRowView
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
        if !scrubberActive {
            scrubMinutes = nil
            locationMenuEntries.removeAll()
        }
        rebuildMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        scrubberActive = false
        scrubMinutes = nil
        locationMenuEntries.removeAll()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        locationMenuEntries.removeAll()
        let displayDate = menuDisplayDate()
        let locations = LocationStore.shared.sortedByOffset()
        let menuWidth = TZBarMenuLayout.preferredWidth(
            locations: locations,
            at: displayDate,
            appVersion: appVersionString,
            scrubberActive: scrubberActive
        )

        for location in locations {
            let time = formattedTime(in: location.timeZoneIdentifier, at: displayDate)
            let phase = dayPhase(in: location.timeZoneIdentifier, at: displayDate)
            let showsDayPhase = AppPreferences.showDayPhaseIcons
            let (item, rowView) = TZBarMenuItemFactory.locationItem(
                location: location,
                width: menuWidth,
                time: time,
                dayPhase: phase,
                showsDayPhase: showsDayPhase
            )
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
            menu.addItem(settingsRow(
                title: "Add…",
                menuWidth: menuWidth,
                action: #selector(showAddPopover),
                showsCheckmarkColumn: false
            ))
            menu.addItem(.separator())
        } else {
            menu.addItem(.separator())
        }

        if scrubberActive {
            let scrubberItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            let minutes = scrubMinutes ?? minutesSinceMidnight(in: TimeZone.current)
            let referenceTimeZone = TimeZone.current
            let scrubDate = date(atMinutesSinceMidnight: minutes, in: referenceTimeZone)
            let showsDayPhase = AppPreferences.showDayPhaseIcons
            scrubberItem.view = TimeScrubberMenuItemView(
                width: menuWidth,
                minutes: minutes,
                referenceTimeZone: referenceTimeZone,
                dayPhase: dayPhase(in: referenceTimeZone.identifier, at: scrubDate),
                showsDayPhase: showsDayPhase,
                onScrub: { [weak self] newMinutes in
                    self?.scrubMinutes = newMinutes
                    self?.updateScrubbedLocationTimes()
                }
            )
            menu.addItem(scrubberItem)
        }

        let settingsItem = TZBarMenuItemFactory.rowItem(
            title: "Settings",
            width: menuWidth,
            content: .gear,
            action: nil,
            target: nil
        )

        let settingsMenu = NSMenu()
        if !locations.isEmpty {
            settingsMenu.addItem(settingsRow(
                title: "Add…",
                menuWidth: menuWidth,
                action: #selector(showAddPopover)
            ))
        }

        settingsMenu.addItem(settingsRow(
            title: "Phase Icons",
            menuWidth: menuWidth,
            action: #selector(toggleDayPhaseIcons(_:)),
            state: AppPreferences.showDayPhaseIcons ? .on : .off
        ))

        if !locations.isEmpty {
            settingsMenu.addItem(settingsRow(
                title: "Time Scrubber",
                menuWidth: menuWidth,
                action: #selector(toggleTimeScrubber(_:)),
                state: scrubberActive ? .on : .off
            ))
        }

        settingsMenu.addItem(settingsRow(
            title: "Launch at Login",
            menuWidth: menuWidth,
            action: #selector(toggleLaunchAtLogin(_:)),
            state: launchAtLoginEnabled ? .on : .off
        ))

        settingsMenu.addItem(.separator())

        settingsMenu.addItem(settingsRow(
            title: "Check for Updates…",
            menuWidth: menuWidth,
            action: #selector(openUpdatesPage(_:)),
            trailing: appVersionString
        ))

        settingsMenu.addItem(settingsRow(
            title: "Report Bug…",
            menuWidth: menuWidth,
            action: #selector(reportBug(_:))
        ))

        settingsMenu.addItem(.separator())

        let quitItem = settingsRow(
            title: "Quit",
            menuWidth: menuWidth,
            action: #selector(quitApp(_:)),
            trailing: "⌘Q",
            monospacedTrailing: true
        )
        quitItem.keyEquivalent = "q"
        settingsMenu.addItem(quitItem)

        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)
    }

    private func settingsRow(
        title: String,
        menuWidth: CGFloat,
        action: Selector?,
        target: AnyObject? = nil,
        trailing: String? = nil,
        monospacedTrailing: Bool = false,
        state: NSControl.StateValue = .off,
        showsCheckmarkColumn: Bool = true
    ) -> NSMenuItem {
        TZBarMenuItemFactory.rowItem(
            title: title,
            width: menuWidth,
            content: .action(
                title: title,
                trailing: trailing,
                monospacedTrailing: monospacedTrailing,
                showsCheckmarkColumn: showsCheckmarkColumn
            ),
            action: action,
            target: target ?? self,
            state: state
        )
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
            entry.view.updateLocation(time: time, dayPhase: phase)
        }
    }

    @objc private func toggleTimeScrubber(_ sender: NSMenuItem) {
        scrubberActive.toggle()
        if scrubberActive {
            scrubMinutes = minutesSinceMidnight(in: TimeZone.current)
        } else {
            scrubMinutes = nil
        }
        rebuildMenu()
    }

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private var appVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        menu.cancelTracking()
        NSApp.terminate(sender)
    }

    @objc private func openUpdatesPage(_ sender: NSMenuItem) {
        menu.cancelTracking()
        guard let url = URL(string: "https://tzbar.evetools.app") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func reportBug(_ sender: NSMenuItem) {
        menu.cancelTracking()
        guard let url = URL(string: "https://github.com/EveToolsHQ/TZBar/issues") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleDayPhaseIcons(_ sender: NSMenuItem) {
        AppPreferences.showDayPhaseIcons.toggle()
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let enable = !launchAtLoginEnabled
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            sender.state = launchAtLoginEnabled ? .on : .off
            sender.view?.needsDisplay = true
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
        menu.cancelTracking()
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
            if let button = pinnedStatusItems[location.id.uuidString]?.button {
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
            let activeKeys = Set(pinned.map(\.id.uuidString))
            for key in pinnedStatusItems.keys where !activeKeys.contains(key) {
                if let item = pinnedStatusItems.removeValue(forKey: key) {
                    NSStatusBar.system.removeStatusItem(item)
                }
            }
            for location in pinned {
                let key = location.id.uuidString
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
            guard let item = pinnedStatusItems[location.id.uuidString] else { continue }
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
        let flag = location.emoji
        let time = formattedTime(in: location.timeZoneIdentifier, at: date)
        let name = location.displayName
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
