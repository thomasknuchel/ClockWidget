import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var clockController: ClockController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        clockController = ClockController()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
