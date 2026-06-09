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
    private var showScrubberOnNextOpen = false
    private var locationMenuEntries: [LocationMenuEntry] = []

    func applicationDidFinishLaunching(_: Notification) {
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

    func menuWillOpen(_ openingMenu: NSMenu) {
        guard openingMenu === menu else { return }
        if showScrubberOnNextOpen {
            showScrubberOnNextOpen = false
            scrubberActive = true
        } else if !scrubberActive {
            scrubMinutes = nil
            locationMenuEntries.removeAll()
        }
        rebuildMenu()
    }

    func menuDidClose(_: NSMenu) {
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
        let menuWidth = TZBarMenuLayout.preferredWidth(
            locations: locations,
            at: displayDate,
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
            menu.addItem(menuItem(title: "Add…", action: #selector(showAddPopover)))
            menu.addItem(.separator())
        } else {
            menu.addItem(.separator())
        }

        if scrubberActive {
            let scrubberItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            let minutes = TimeScrubberMenuItemView.snappedMinutes(
                scrubMinutes ?? minutesSinceMidnight(in: TimeZone.current)
            )
            let referenceTimeZone = TimeZone.current
            let showsDayPhase = AppPreferences.showDayPhaseIcons
            scrubberItem.view = TimeScrubberMenuItemView(
                width: menuWidth,
                minutes: minutes,
                referenceTimeZone: referenceTimeZone,
                showsDayPhase: showsDayPhase,
                onScrub: { [weak self] newMinutes in
                    self?.scrubMinutes = newMinutes
                    self?.updateScrubbedLocationTimes()
                }
            )
            menu.addItem(scrubberItem)
        }

        let settingsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        settingsItem.image = Self.settingsGearImage
        settingsItem.submenu = buildSettingsMenu(locationsEmpty: locations.isEmpty)
        menu.addItem(settingsItem)
    }

    private static let settingsGearImage: NSImage? = {
        guard let image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        else { return nil }
        image.isTemplate = true
        return image
    }()

    private func buildSettingsMenu(locationsEmpty: Bool) -> NSMenu {
        let settingsMenu = NSMenu()
        if !locationsEmpty {
            settingsMenu.addItem(menuItem(title: "Add…", action: #selector(showAddPopover)))
        }

        settingsMenu.addItem(menuItem(
            title: "Phase Icons",
            action: #selector(toggleDayPhaseIcons(_:)),
            state: AppPreferences.showDayPhaseIcons ? .on : .off
        ))

        if !locationsEmpty {
            settingsMenu.addItem(menuItem(
                title: "Time Scrubber",
                action: #selector(toggleTimeScrubber(_:)),
                state: scrubberActive ? .on : .off
            ))
        }

        settingsMenu.addItem(menuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            state: launchAtLoginEnabled ? .on : .off
        ))

        settingsMenu.addItem(.separator())

        settingsMenu.addItem(menuItem(
            title: "Check for Updates…",
            action: #selector(openUpdatesPage(_:))
        ))
        settingsMenu.addItem(menuItem(title: "Report Bug…", action: #selector(reportBug(_:))))

        let versionItem = NSMenuItem(title: appVersionCaption, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        settingsMenu.addItem(versionItem)

        settingsMenu.addItem(.separator())
        settingsMenu.addItem(menuItem(
            title: "Quit",
            action: #selector(quitApp(_:)),
            keyEquivalent: "q"
        ))
        return settingsMenu
    }

    private func menuItem(
        title: String,
        action: Selector?,
        state: NSControl.StateValue = .off,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.state = state
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
            entry.view.updateLocation(time: time, dayPhase: phase)
        }
    }

    @objc private func toggleTimeScrubber(_: NSMenuItem) {
        if scrubberActive {
            scrubberActive = false
            scrubMinutes = nil
        } else {
            scrubMinutes = TimeScrubberMenuItemView.snappedMinutes(
                minutesSinceMidnight(in: TimeZone.current)
            )
            showScrubberOnNextOpen = true
        }
        // Settings submenu can't refresh main menu; close all menus then reopen.
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

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private var appVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var appVersionCaption: String {
        "TZBar v\(appVersionString)"
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        menu.cancelTracking()
        NSApp.terminate(sender)
    }

    @objc private func openUpdatesPage(_: NSMenuItem) {
        menu.cancelTracking()
        guard let url = URL(string: "https://evetools.app/en/tzbar") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func reportBug(_: NSMenuItem) {
        menu.cancelTracking()
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "hey@evetools.app"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        components.queryItems = [
            URLQueryItem(name: "subject", value: "TZBar bug report"),
            URLQueryItem(
                name: "body",
                value: """
                TZBar version: \(appVersionString)
                macOS: \(os)

                Describe the issue:


                """
            ),
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleDayPhaseIcons(_: NSMenuItem) {
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
