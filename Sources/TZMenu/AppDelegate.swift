import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var addPanel: AddLocationPanelController?

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
            item.isEnabled = false
            menu.addItem(item)
        }

        if !LocationStore.shared.locations.isEmpty {
            menu.addItem(.separator())
        }

        let addItem = NSMenuItem(title: "Add…", action: #selector(showAddPanel), keyEquivalent: "")
        addItem.target = self
        menu.addItem(addItem)
    }

    @objc private func showAddPanel() {
        if addPanel == nil {
            addPanel = AddLocationPanelController { [weak self] in
                self?.rebuildMenu()
            }
        }
        addPanel?.showPanel()
    }

}
