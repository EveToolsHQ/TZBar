import AppKit

enum MenuMetrics {
    static let rowHeight: CGFloat = 22
    static let leadingInset: CGFloat = 18
    static let trailingInset: CGFloat = 18
    static let checkmarkSymbolSize: CGFloat = 13
    static let dayPhaseSymbolSize: CGFloat = 13
    static let timeToDayPhaseGap: CGFloat = 6
}

enum MenuRowContent {
    case location(flag: String, name: String, time: String, dayPhase: DayPhase, showsDayPhase: Bool)
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
        guard bounds.contains(point) else { return nil }
        // Rows with a submenu must not steal mouse events — AppKit/Carbon handles hover and click.
        if enclosingMenuItem?.submenu != nil { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard let item = enclosingMenuItem,
              let target = item.target,
              let action = item.action
        else { return }
        NSApp.sendAction(action, to: target, from: item)
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
        scrubberActive: Bool
    ) -> CGFloat {
        max(
            locationRowsWidth(locations: locations, at: date),
            scrubberActive ? 260 : 0
        )
    }

    private static func locationRowsWidth(locations: [SavedLocation], at date: Date) -> CGFloat {
        let nameFont = NSFont.menuFont(ofSize: 0)
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: nameFont.pointSize, weight: .regular)
        var width: CGFloat = 200

        for location in locations {
            let name = "\(location.emoji)  \(location.displayName)"
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
}

enum TZBarMenuItemFactory {
    static func locationItem(
        location: SavedLocation,
        width: CGFloat,
        time: String,
        dayPhase: DayPhase,
        showsDayPhase: Bool
    ) -> (NSMenuItem, MenuRowView) {
        let item = NSMenuItem(
            title: "\(location.emoji)  \(location.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        let view = MenuRowView(
            width: width,
            content: .location(
                flag: location.emoji,
                name: location.displayName,
                time: time,
                dayPhase: dayPhase,
                showsDayPhase: showsDayPhase
            )
        )
        item.view = view
        return (item, view)
    }
}
