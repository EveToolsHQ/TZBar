import AppKit
import ServiceManagement

private final class LocationMenuTag: NSObject {
    let location: SavedLocation

    init(location: SavedLocation) {
        self.location = location
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var addPopover: AddLocationPopoverController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "globe", accessibilityDescription: "World Clock") {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                button.image = image
                button.title = ""
            } else {
                button.title = "🌐"
            }
            button.toolTip = "World Clock"
        }

        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "q"
            else { return event }
            NSApp.terminate(nil)
            return nil
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let now = Date()

        for location in LocationStore.shared.sortedByOffset() {
            let flag = flagEmoji(for: location.countryCode)
            let time = formattedTime(in: location.timeZoneIdentifier, at: now)
            let item = NSMenuItem(
                title: "\(flag)  \(location.displayName)  \(time)",
                action: nil,
                keyEquivalent: ""
            )

            let locationMenu = NSMenu()
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

        if !LocationStore.shared.locations.isEmpty {
            menu.addItem(.separator())
        }

        let addItem = NSMenuItem(title: "Add…", action: #selector(showAddPopover), keyEquivalent: "")
        addItem.target = self
        menu.addItem(addItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        settingsItem.toolTip = "Settings"
        if let gear = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings") {
            gear.isTemplate = true
            settingsItem.image = gear
        }

        let settingsMenu = NSMenu()

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

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
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

    @objc private func deleteLocation(_ sender: NSMenuItem) {
        guard let tag = sender.representedObject as? LocationMenuTag else { return }
        LocationStore.shared.remove(tag.location)
        rebuildMenu()
    }

    @objc private func showAddPopover() {
        guard statusItem.button != nil else { return }
        if addPopover == nil {
            addPopover = AddLocationPopoverController { [weak self] in
                self?.rebuildMenu()
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            self.addPopover?.toggle(relativeTo: button.bounds, of: button)
        }
    }
}
