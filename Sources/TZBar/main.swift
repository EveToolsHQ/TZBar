import AppKit

/// NSApplication.delegate is weak; keep a strong reference for app lifetime.
private let appDelegate = AppDelegate()

Main.main()

enum Main {
    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
