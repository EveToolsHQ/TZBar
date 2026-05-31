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
    static let dayPhaseTrailingInset: CGFloat = 6
    static let timeToDayPhaseSpacing: CGFloat = 6
}

private final class LocationMenuItemView: NSView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let dayPhaseView = NSImageView()

    init(flag: String, name: String, time: String, dayPhase: DayPhase, width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))

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

        if let image = NSImage(
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

        addSubview(nameLabel)
        addSubview(timeLabel)
        addSubview(dayPhaseView)

        let symbolSize = LocationMenuMetrics.dayPhaseSymbolSize
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -12),
            dayPhaseView.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -LocationMenuMetrics.dayPhaseTrailingInset
            ),
            dayPhaseView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dayPhaseView.widthAnchor.constraint(equalToConstant: symbolSize),
            dayPhaseView.heightAnchor.constraint(equalToConstant: symbolSize),
            timeLabel.trailingAnchor.constraint(
                equalTo: dayPhaseView.leadingAnchor,
                constant: -LocationMenuMetrics.timeToDayPhaseSpacing
            ),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

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
        let locations = LocationStore.shared.sortedByOffset()
        let menuWidth = locationMenuWidth(for: locations, at: now)

        for location in locations {
            let flag = flagEmoji(for: location.countryCode)
            let name = shortDisplayName(location.displayName)
            let time = formattedTime(in: location.timeZoneIdentifier, at: now)
            let phase = dayPhase(in: location.timeZoneIdentifier, at: now)
            let item = NSMenuItem(title: "\(flag)  \(name)  \(time)", action: nil, keyEquivalent: "")
            item.view = LocationMenuItemView(flag: flag, name: name, time: time, dayPhase: phase, width: menuWidth)

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

        if !locations.isEmpty {
            menu.addItem(.separator())
        }

        let addItem = NSMenuItem(title: "Add…", action: #selector(showAddPopover), keyEquivalent: "")
        addItem.target = self
        menu.addItem(addItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: nil, keyEquivalent: "")
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

    private func locationMenuWidth(for locations: [SavedLocation], at date: Date) -> CGFloat {
        let nameFont = NSFont.menuFont(ofSize: 0)
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: nameFont.pointSize, weight: .regular)
        var width: CGFloat = 200

        for location in locations {
            let name = "\(flagEmoji(for: location.countryCode))  \(shortDisplayName(location.displayName))"
            let time = formattedTime(in: location.timeZoneIdentifier, at: date)
            let nameWidth = (name as NSString).size(withAttributes: [.font: nameFont]).width
            let timeWidth = (time as NSString).size(withAttributes: [.font: timeFont]).width
            let dayPhaseWidth = LocationMenuMetrics.dayPhaseSymbolSize
                + LocationMenuMetrics.timeToDayPhaseSpacing
                + LocationMenuMetrics.dayPhaseTrailingInset
            width = max(width, nameWidth + timeWidth + dayPhaseWidth + 34)
        }

        return ceil(width)
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
