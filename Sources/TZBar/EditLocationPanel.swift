import AppKit

final class EditLocationPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let viewController: EditLocationViewController
    private var resignActiveObserver: NSObjectProtocol?

    init(location: SavedLocation, onEdited: @escaping () -> Void) {
        viewController = EditLocationViewController(location: location)
        super.init()
        popover.contentViewController = viewController
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        viewController.onEmojiChanged = onEdited
        viewController.onFinished = { [weak self] in
            onEdited()
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

    func show(relativeTo positioningRect: NSRect, of positioningView: NSView) {
        viewController.prepareForDisplay()
        popover.show(relativeTo: positioningRect, of: positioningView, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func popoverDidClose(_: Notification) {
        viewController.prepareForDisplay()
    }
}

final class EditLocationViewController: NSViewController, NSTextFieldDelegate {
    private enum Layout {
        static let width: CGFloat = 280
        static let padding: CGFloat = 12
        static let spacing: CGFloat = 8
        static let emojiSlotWidth: CGFloat = 44
        static let height: CGFloat = 56
    }

    var onEmojiChanged: (() -> Void)?
    var onFinished: (() -> Void)?

    private let location: SavedLocation
    private let emojiSlot = NSView()
    private let emojiButton = NSButton()
    private let hiddenEmojiInput = NSTextField()
    private let nameField = NSTextField()
    private var selectedEmoji = ""
    private var emojiTextObserver: NSObjectProtocol?

    init(location: SavedLocation) {
        self.location = location
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        emojiButton.bezelStyle = .rounded
        emojiButton.font = NSFont.systemFont(ofSize: NSFont.systemFontSize + 4)
        emojiButton.target = self
        emojiButton.action = #selector(showEmojiPicker)
        emojiButton.toolTip = "Choose emoji"

        hiddenEmojiInput.isEditable = true
        hiddenEmojiInput.isBordered = false
        hiddenEmojiInput.drawsBackground = false
        hiddenEmojiInput.alphaValue = 0
        hiddenEmojiInput.alignment = .center
        hiddenEmojiInput.focusRingType = .none
        hiddenEmojiInput.delegate = self
        hiddenEmojiInput.maximumNumberOfLines = 1
        hiddenEmojiInput.cell?.wraps = false
        hiddenEmojiInput.cell?.isScrollable = true
        hiddenEmojiInput.cell?.alignment = .center

        nameField.placeholderString = "Name"
        nameField.focusRingType = .default
        nameField.delegate = self
        nameField.maximumNumberOfLines = 1
        nameField.cell?.wraps = false
        nameField.cell?.isScrollable = true

        emojiSlot.translatesAutoresizingMaskIntoConstraints = false
        hiddenEmojiInput.translatesAutoresizingMaskIntoConstraints = false
        emojiButton.translatesAutoresizingMaskIntoConstraints = false
        emojiSlot.addSubview(hiddenEmojiInput)
        emojiSlot.addSubview(emojiButton)

        let row = NSStackView(views: [emojiSlot, nameField])
        row.orientation = .horizontal
        row.spacing = Layout.spacing
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(row)

        NSLayoutConstraint.activate([
            emojiSlot.widthAnchor.constraint(equalToConstant: Layout.emojiSlotWidth),
            hiddenEmojiInput.leadingAnchor.constraint(equalTo: emojiSlot.leadingAnchor),
            hiddenEmojiInput.trailingAnchor.constraint(equalTo: emojiSlot.trailingAnchor),
            hiddenEmojiInput.topAnchor.constraint(equalTo: emojiSlot.topAnchor),
            hiddenEmojiInput.bottomAnchor.constraint(equalTo: emojiSlot.bottomAnchor),
            emojiButton.leadingAnchor.constraint(equalTo: emojiSlot.leadingAnchor),
            emojiButton.trailingAnchor.constraint(equalTo: emojiSlot.trailingAnchor),
            emojiButton.topAnchor.constraint(equalTo: emojiSlot.topAnchor),
            emojiButton.bottomAnchor.constraint(equalTo: emojiSlot.bottomAnchor),
            row.topAnchor.constraint(equalTo: view.topAnchor, constant: Layout.padding),
            row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.padding),
            row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.padding),
            row.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Layout.padding),
        ])

        emojiTextObserver = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let editor = self.hiddenEmojiInput.currentEditor(),
                  notification.object as? NSText === editor
            else { return }
            self.applyEmojiFromInput()
        }
    }

    deinit {
        if let emojiTextObserver {
            NotificationCenter.default.removeObserver(emojiTextObserver)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(nameField)
        nameField.currentEditor()?.selectAll(nil)
    }

    func prepareForDisplay() {
        loadViewIfNeeded()
        selectedEmoji = location.emoji
        emojiButton.title = selectedEmoji
        hiddenEmojiInput.stringValue = ""
        nameField.stringValue = location.displayName
    }

    @objc private func showEmojiPicker() {
        hiddenEmojiInput.stringValue = ""
        view.window?.makeFirstResponder(hiddenEmojiInput)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.orderFrontCharacterPalette(self.hiddenEmojiInput)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as? NSTextField === hiddenEmojiInput else { return }
        applyEmojiFromInput()
    }

    func control(_ control: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === nameField,
              commandSelector == #selector(NSResponder.insertNewline(_:))
        else { return false }
        commitName()
        return true
    }

    private func applyEmojiFromInput() {
        let raw = hiddenEmojiInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = raw.first else { return }

        let emoji = String(first)
        selectedEmoji = emoji
        emojiButton.title = emoji
        hiddenEmojiInput.stringValue = ""

        LocationStore.shared.setEmoji(emoji, for: location)
        onEmojiChanged?()
    }

    private func commitName() {
        let nameInput = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nameInput.isEmpty else {
            onFinished?()
            return
        }
        LocationStore.shared.setDisplayName(nameInput, for: location)
        onFinished?()
    }
}
