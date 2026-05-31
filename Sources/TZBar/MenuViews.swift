import AppKit

enum MenuMetrics {
    static let rowHeight: CGFloat = 22
    static let leadingInset: CGFloat = 18
    static let trailingInset: CGFloat = 18
    static let checkmarkColumnWidth: CGFloat = 18
    static let checkmarkSymbolSize: CGFloat = 13
    static let titleToTrailingGap: CGFloat = 12
    static let dayPhaseSymbolSize: CGFloat = 13
    static let timeToDayPhaseGap: CGFloat = 6
}

enum MenuRowContent {
    case location(flag: String, name: String, time: String, dayPhase: DayPhase, showsDayPhase: Bool)
    case action(
        title: String,
        trailing: String?,
        monospacedTrailing: Bool,
        showsCheckmarkColumn: Bool
    )
    case gear
}

/// Drawn menu row. Custom `NSMenuItem.view` does not fire actions automatically — we forward clicks.
final class MenuRowView: NSView {
    private var content: MenuRowContent

    init(width: CGFloat, content: MenuRowContent) {
        self.content = content
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: MenuMetrics.rowHeight))
        autoresizingMask = [.width]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func updateLocation(time: String, dayPhase: DayPhase) {
        guard case let .location(flag, name, _, _, showsDayPhase) = content else { return }
        content = .location(
            flag: flag,
            name: name,
            time: time,
            dayPhase: dayPhase,
            showsDayPhase: showsDayPhase
        )
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let item = enclosingMenuItem else { return }
        if let target = item.target, let action = item.action {
            NSApp.sendAction(action, to: target, from: item)
            return
        }
        super.mouseDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = enclosingMenuItem?.isHighlighted == true
        applyHighlightBackground(highlighted, in: dirtyRect)

        switch content {
        case let .location(flag, name, time, dayPhase, showsDayPhase):
            drawLocation(
                flag: flag,
                name: name,
                time: time,
                dayPhase: dayPhase,
                showsDayPhase: showsDayPhase,
                highlighted: highlighted
            )
        case let .action(title, trailing, monospacedTrailing, showsCheckmarkColumn):
            drawAction(
                title: title,
                trailing: trailing,
                monospacedTrailing: monospacedTrailing,
                showsCheckmarkColumn: showsCheckmarkColumn,
                highlighted: highlighted
            )
        case .gear:
            drawGear(highlighted: highlighted)
        }
    }

    private func applyHighlightBackground(_ highlighted: Bool, in dirtyRect: NSRect) {
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            dirtyRect.fill()
        }
    }

    private func menuFont() -> NSFont { NSFont.menuFont(ofSize: 0) }

    private func titleColor(highlighted: Bool) -> NSColor {
        highlighted ? .selectedMenuItemTextColor : .labelColor
    }

    private func secondaryColor(highlighted: Bool) -> NSColor {
        highlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
    }

    private func drawTemplateSymbol(
        _ name: String,
        in rect: NSRect,
        pointSize: CGFloat,
        color: NSColor
    ) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let symbol = image.withSymbolConfiguration(config) else { return }
        symbol.draw(in: rect)
    }

    private func drawAction(
        title: String,
        trailing: String?,
        monospacedTrailing: Bool,
        showsCheckmarkColumn: Bool,
        highlighted: Bool
    ) {
        let font = menuFont()
        let titleColor = titleColor(highlighted: highlighted)
        let detailColor = secondaryColor(highlighted: highlighted)
        var titleX = MenuMetrics.leadingInset

        if showsCheckmarkColumn {
            let checkOrigin = NSPoint(
                x: MenuMetrics.leadingInset,
                y: (bounds.height - MenuMetrics.checkmarkSymbolSize) / 2
            )
            if enclosingMenuItem?.state == .on {
                drawTemplateSymbol(
                    "checkmark",
                    in: NSRect(
                        origin: checkOrigin,
                        size: NSSize(
                            width: MenuMetrics.checkmarkSymbolSize,
                            height: MenuMetrics.checkmarkSymbolSize
                        )
                    ),
                    pointSize: font.pointSize * 0.85,
                    color: titleColor
                )
            }
            titleX += MenuMetrics.checkmarkColumnWidth
        }

        let titleY = (bounds.height - font.boundingRectForFont.height) / 2 + 1
        (title as NSString).draw(
            at: NSPoint(x: titleX, y: titleY),
            withAttributes: [.font: font, .foregroundColor: titleColor]
        )

        if let trailing {
            let trailingFont = monospacedTrailing
                ? NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular)
                : font
            let size = (trailing as NSString).size(withAttributes: [.font: trailingFont])
            let point = NSPoint(
                x: bounds.maxX - MenuMetrics.trailingInset - size.width,
                y: (bounds.height - size.height) / 2
            )
            (trailing as NSString).draw(
                at: point,
                withAttributes: [.font: trailingFont, .foregroundColor: detailColor]
            )
        }
    }

    private func drawLocation(
        flag: String,
        name: String,
        time: String,
        dayPhase: DayPhase,
        showsDayPhase: Bool,
        highlighted: Bool
    ) {
        let nameFont = menuFont()
        let timeFont = NSFont.monospacedDigitSystemFont(
            ofSize: nameFont.pointSize,
            weight: .regular
        )
        let title = "\(flag)  \(name)"
        let titleColor = titleColor(highlighted: highlighted)
        let timeColor = secondaryColor(highlighted: highlighted)

        let titleY = (bounds.height - nameFont.boundingRectForFont.height) / 2 + 1
        (title as NSString).draw(
            at: NSPoint(x: MenuMetrics.leadingInset, y: titleY),
            withAttributes: [.font: nameFont, .foregroundColor: titleColor]
        )

        var trailingX = bounds.maxX - MenuMetrics.trailingInset
        if showsDayPhase {
            let symbolRect = NSRect(
                x: trailingX - MenuMetrics.dayPhaseSymbolSize,
                y: (bounds.height - MenuMetrics.dayPhaseSymbolSize) / 2,
                width: MenuMetrics.dayPhaseSymbolSize,
                height: MenuMetrics.dayPhaseSymbolSize
            )
            drawTemplateSymbol(
                dayPhase.symbolName,
                in: symbolRect,
                pointSize: nameFont.pointSize * 0.9,
                color: timeColor
            )
            trailingX -= MenuMetrics.dayPhaseSymbolSize + MenuMetrics.timeToDayPhaseGap
        }

        let timeSize = (time as NSString).size(withAttributes: [.font: timeFont])
        let timePoint = NSPoint(
            x: trailingX - timeSize.width,
            y: (bounds.height - timeSize.height) / 2
        )
        (time as NSString).draw(
            at: timePoint,
            withAttributes: [.font: timeFont, .foregroundColor: timeColor]
        )
    }

    private func drawGear(highlighted: Bool) {
        let color = secondaryColor(highlighted: highlighted)
        let rect = NSRect(
            x: bounds.maxX - MenuMetrics.trailingInset - MenuMetrics.checkmarkSymbolSize,
            y: (bounds.height - MenuMetrics.checkmarkSymbolSize) / 2,
            width: MenuMetrics.checkmarkSymbolSize,
            height: MenuMetrics.checkmarkSymbolSize
        )
        drawTemplateSymbol("gearshape", in: rect, pointSize: menuFont().pointSize * 0.9, color: color)
    }
}

final class TimeScrubberMenuItemView: NSView {
    private static let sliderToTimeGap: CGFloat = 8

    private static var timeLabelWidth: CGFloat {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.menuFont(ofSize: 0).pointSize,
            weight: .regular
        )
        return ceil(("88:88" as NSString).size(withAttributes: [.font: font]).width)
    }

    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1439, target: nil, action: nil)
    private let timeLabel = NSTextField(labelWithString: "")
    private let phaseImageView = NSImageView()
    private let onScrub: (Int) -> Void
    private let referenceTimeZone: TimeZone
    private let showsDayPhase: Bool

    init(
        width: CGFloat,
        minutes: Int,
        referenceTimeZone: TimeZone,
        dayPhase: DayPhase,
        showsDayPhase: Bool,
        onScrub: @escaping (Int) -> Void
    ) {
        self.onScrub = onScrub
        self.referenceTimeZone = referenceTimeZone
        self.showsDayPhase = showsDayPhase
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: MenuMetrics.rowHeight))
        autoresizingMask = [.width]

        let timeFont = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.menuFont(ofSize: 0).pointSize,
            weight: .regular
        )
        timeLabel.font = timeFont
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.alignment = .right
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        phaseImageView.translatesAutoresizingMaskIntoConstraints = false
        phaseImageView.imageScaling = .scaleProportionallyUpOrDown
        phaseImageView.isHidden = !showsDayPhase

        slider.isContinuous = true
        slider.controlSize = .small
        slider.doubleValue = Double(minutes)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.target = self
        slider.action = #selector(sliderChanged)

        addSubview(slider)
        addSubview(timeLabel)
        addSubview(phaseImageView)

        let phaseWidth = showsDayPhase ? MenuMetrics.dayPhaseSymbolSize : 0
        let phaseGap = showsDayPhase ? MenuMetrics.timeToDayPhaseGap : 0

        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuMetrics.leadingInset),
            slider.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -Self.sliderToTimeGap),
            slider.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            slider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            timeLabel.trailingAnchor.constraint(
                equalTo: phaseImageView.leadingAnchor,
                constant: -phaseGap
            ),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeLabel.widthAnchor.constraint(equalToConstant: Self.timeLabelWidth),
            phaseImageView.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -MenuMetrics.trailingInset
            ),
            phaseImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            phaseImageView.widthAnchor.constraint(equalToConstant: phaseWidth),
            phaseImageView.heightAnchor.constraint(equalToConstant: phaseWidth),
        ])

        updateDisplay(minutes: minutes, dayPhase: dayPhase)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point), scrubbingRect.contains(point) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        scrub(with: event)
        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: .infinity,
            mode: .eventTracking,
            handler: { [weak self] event, stop in
                guard let self, let event else {
                    stop.pointee = true
                    return
                }
                switch event.type {
                case .leftMouseDragged:
                    self.scrub(with: event)
                case .leftMouseUp:
                    stop.pointee = true
                default:
                    break
                }
            }
        )
    }

    @objc private func sliderChanged() {
        let minutes = Int(slider.doubleValue.rounded())
        let date = date(atMinutesSinceMidnight: minutes, in: referenceTimeZone)
        let phase = dayPhase(in: referenceTimeZone.identifier, at: date)
        updateDisplay(minutes: minutes, dayPhase: phase)
        onScrub(minutes)
    }

    private func updateDisplay(minutes: Int, dayPhase: DayPhase) {
        let date = date(atMinutesSinceMidnight: minutes, in: referenceTimeZone)
        timeLabel.stringValue = formattedTime(in: referenceTimeZone.identifier, at: date)
        guard showsDayPhase else { return }
        let menuFont = NSFont.menuFont(ofSize: 0)
        let config = NSImage.SymbolConfiguration(pointSize: menuFont.pointSize * 0.9, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor]))
        phaseImageView.image = NSImage(systemSymbolName: dayPhase.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        phaseImageView.contentTintColor = .secondaryLabelColor
        phaseImageView.setAccessibilityLabel(dayPhase.accessibilityLabel)
    }

    private var scrubbingRect: NSRect {
        let trackMinX = MenuMetrics.leadingInset
        let trackMaxX = bounds.width - Self.trailingColumnWidth(showsDayPhase: showsDayPhase)
        return NSRect(
            x: trackMinX,
            y: bounds.minY,
            width: max(0, trackMaxX - trackMinX),
            height: bounds.height
        )
    }

    private static func trailingColumnWidth(showsDayPhase: Bool) -> CGFloat {
        var width = MenuMetrics.trailingInset + timeLabelWidth
        if showsDayPhase {
            width += MenuMetrics.timeToDayPhaseGap + MenuMetrics.dayPhaseSymbolSize
        }
        return width
    }

    private func scrub(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let rect = scrubbingRect
        guard rect.width > 0 else { return }
        let fraction = (point.x - rect.minX) / rect.width
        let clamped = max(0, min(1, fraction))
        slider.doubleValue = slider.minValue + clamped * (slider.maxValue - slider.minValue)
        sliderChanged()
    }
}

enum TZBarMenuLayout {
    static func preferredWidth(
        locations: [SavedLocation],
        at date: Date,
        appVersion: String,
        scrubberActive: Bool
    ) -> CGFloat {
        max(
            locationRowsWidth(locations: locations, at: date),
            settingsRowsWidth(appVersion: appVersion),
            scrubberActive ? 260 : 0
        )
    }

    private static func locationRowsWidth(locations: [SavedLocation], at date: Date) -> CGFloat {
        let nameFont = NSFont.menuFont(ofSize: 0)
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: nameFont.pointSize, weight: .regular)
        var width: CGFloat = 200

        for location in locations {
            let name = "\(location.emojiText)  \(location.labelText)"
            let time = formattedTime(in: location.timeZoneIdentifier, at: date)
            let nameWidth = (name as NSString).size(withAttributes: [.font: nameFont]).width
            let timeWidth = (time as NSString).size(withAttributes: [.font: timeFont]).width
            let trailing: CGFloat
            if AppPreferences.showDayPhaseIcons {
                trailing = MenuMetrics.dayPhaseSymbolSize
                    + MenuMetrics.timeToDayPhaseGap
                    + MenuMetrics.trailingInset
            } else {
                trailing = MenuMetrics.trailingInset
            }
            width = max(width, nameWidth + timeWidth + trailing + MenuMetrics.leadingInset)
        }
        return ceil(width)
    }

    private static func settingsRowsWidth(appVersion: String) -> CGFloat {
        let font = NSFont.menuFont(ofSize: 0)
        let chrome = MenuMetrics.leadingInset
            + MenuMetrics.checkmarkColumnWidth
            + MenuMetrics.titleToTrailingGap
            + MenuMetrics.trailingInset
        var width: CGFloat = 200
        let rows: [(String, String?)] = [
            ("Add…", nil),
            ("Phase Icons", nil),
            ("Time Scrubber", nil),
            ("Launch at Login", nil),
            ("Check for Updates…", appVersion),
            ("Report Bug…", nil),
            ("Quit", "⌘Q"),
        ]
        for (title, trailing) in rows {
            let titleWidth = (title as NSString).size(withAttributes: [.font: font]).width
            let trailingWidth = trailing.map {
                ($0 as NSString).size(withAttributes: [.font: font]).width
            } ?? 0
            width = max(width, chrome + titleWidth + trailingWidth)
        }
        return ceil(width)
    }
}

enum TZBarMenuItemFactory {
    static func rowItem(
        title: String,
        width: CGFloat,
        content: MenuRowContent,
        action: Selector?,
        target: AnyObject?,
        state: NSControl.StateValue = .off,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        item.state = state
        item.view = MenuRowView(width: width, content: content)
        return item
    }

    static func locationItem(
        location: SavedLocation,
        width: CGFloat,
        time: String,
        dayPhase: DayPhase,
        showsDayPhase: Bool
    ) -> (NSMenuItem, MenuRowView) {
        let item = NSMenuItem(
            title: "\(location.emojiText)  \(location.labelText)",
            action: nil,
            keyEquivalent: ""
        )
        let view = MenuRowView(
            width: width,
            content: .location(
                flag: location.emojiText,
                name: location.labelText,
                time: time,
                dayPhase: dayPhase,
                showsDayPhase: showsDayPhase
            )
        )
        item.view = view
        return (item, view)
    }
}
