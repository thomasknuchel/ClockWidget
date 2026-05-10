import AppKit
import Foundation

// MARK: - Config
struct ItemConfig: Codable {
    var show: Bool; var size: Double; var color: String; var font: String; var spacing: Double
}
struct Config: Codable {
    var weekday: ItemConfig; var date: ItemConfig; var time: ItemConfig
    var x: Double; var y: Double
    static let `default` = Config(
        weekday: ItemConfig(show: true, size: 22, color: "#FFFFFF", font: "HelveticaNeue-Light", spacing: 4),
        date:    ItemConfig(show: true, size: 22, color: "#FFFFFF", font: "HelveticaNeue-Light", spacing: 4),
        time:    ItemConfig(show: true, size: 72, color: "#FFFFFF", font: "HelveticaNeue-Thin", spacing: 10),
        x: 40, y: 80)
    static var url: URL { URL(fileURLWithPath: NSHomeDirectory() + "/.clockwidget.json") }
    static func load() -> Config {
        guard let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(Config.self, from: data)
        else { return .default }
        return cfg
    }
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Config.url)
    }
}

func nsColor(hex: String) -> NSColor {
    let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard h.count == 6 else { return .white }
    let r = CGFloat(UInt8(h.prefix(2), radix: 16) ?? 255) / 255
    let g = CGFloat(UInt8(h.dropFirst(2).prefix(2), radix: 16) ?? 255) / 255
    let b = CGFloat(UInt8(h.dropFirst(4), radix: 16) ?? 255) / 255
    return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
}
func hexColor(_ c: NSColor) -> String {
    guard let rgb = c.usingColorSpace(.sRGB) else { return "#ffffff" }
    return String(format: "#%02x%02x%02x",
        Int(rgb.redComponent*255), Int(rgb.greenComponent*255), Int(rgb.blueComponent*255))
}
func makeFont(name: String, size: Double) -> NSFont {
    NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: .light)
}

var gSettingsPanel: SettingsPanel?

// MARK: - App Delegate
@objc(AppDelegate)
class AppDelegate: NSObject, NSApplicationDelegate {
    var clockWindow: NSWindow?
    // Fixed set of 3 labels — never removed, just repositioned/hidden
    var lblWeekday = NSTextField()
    var lblDate    = NSTextField()
    var lblTime    = NSTextField()
    var statusItem: NSStatusItem?
    var timer: Timer?
    var config = Config.load()
    var fmtWeekday = DateFormatter()
    var fmtDate    = DateFormatter()
    var fmtTime    = DateFormatter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        fmtWeekday.dateFormat = "EEEE,"
        fmtDate.dateFormat    = "dd. MMMM yyyy,"
        fmtTime.dateFormat    = "HH:mm"

        // Build status bar BEFORE switching to accessory policy
        buildMenuBar()

        buildWindow()
        applyConfig()
        updateClock()

        timer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(tickTimer),
            userInfo: nil,
            repeats: true)

        // Switch to accessory AFTER menubar is built — hides dock icon
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc func tickTimer() {
        updateClock()
    }

    func buildWindow() {
        guard clockWindow == nil else { return }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 280),
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        win.backgroundColor = .clear
        win.isOpaque = false
        // Stay below all normal windows but above desktop wallpaper
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        win.hasShadow = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.isReleasedWhenClosed = false
        clockWindow = win

        // Add all 3 labels once — never remove them
        for lbl in [lblWeekday, lblDate, lblTime] {
            lbl.stringValue = ""
            lbl.backgroundColor = .clear
            lbl.isBezeled = false
            lbl.isEditable = false
            lbl.isSelectable = false
            lbl.drawsBackground = false
            lbl.cell?.wraps = false
            lbl.cell?.isScrollable = true
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.7)
            shadow.shadowOffset = NSSize(width: 1, height: -1)
            shadow.shadowBlurRadius = 4
            lbl.shadow = shadow
            win.contentView?.addSubview(lbl)
        }

        win.orderFrontRegardless()
    }

    // Apply config to existing labels — no subview add/remove
    func applyConfig() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sFrame = screen.frame
        let winW: CGFloat = 700, winH: CGFloat = 280
        let winX = max(0, min(CGFloat(config.x), sFrame.width - winW))
        let winY = CGFloat(config.y)  // user controls exact position
        clockWindow?.setFrameOrigin(NSPoint(x: winX, y: winY))

        let items: [(NSTextField, ItemConfig)] = [
            (lblWeekday, config.weekday),
            (lblDate,    config.date),
            (lblTime,    config.time)
        ]

        var yCursor: CGFloat = winH - 10
        for (lbl, blk) in items {
            if blk.show {
                let h = CGFloat(blk.size + blk.spacing)
                yCursor -= h
                lbl.frame = NSRect(x: 0, y: yCursor, width: 680, height: h + 6)
                lbl.font = makeFont(name: blk.font, size: blk.size)
                lbl.textColor = nsColor(hex: blk.color)
                lbl.isHidden = false
            } else {
                lbl.isHidden = true
            }
        }
    }

    func updateClock() {
        let now = Date()
        if !lblWeekday.isHidden { lblWeekday.stringValue = fmtWeekday.string(from: now) }
        if !lblDate.isHidden    { lblDate.stringValue    = fmtDate.string(from: now) }
        if !lblTime.isHidden    { lblTime.stringValue    = fmtTime.string(from: now) }
    }

    func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "🕐"
        let menu = NSMenu()
        menu.autoenablesItems = false
        let s = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        s.target = self; s.isEnabled = true; menu.addItem(s)
        menu.addItem(.separator())
        let q = NSMenuItem(title: "Quit ClockWidget", action: #selector(quitApp), keyEquivalent: "q")
        q.target = self; q.isEnabled = true; menu.addItem(q)
        statusItem?.menu = menu
    }

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let existing = gSettingsPanel, existing.window?.isVisible == true {
                existing.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            let panel = SettingsPanel(config: self.config) { c in
                c.save()
                // Relaunch via open command - most reliable on macOS
                let bundlePath = Bundle.main.bundlePath
                let script = "sleep 0.5; open '\(bundlePath)'"
                let task = Process()
                task.launchPath = "/bin/sh"
                task.arguments = ["-c", script]
                task.launch()
                NSApp.terminate(nil)
            }
            gSettingsPanel = panel
            panel.show()
        }
    }

    @objc func quitApp() {
        timer?.invalidate()
        config.save()
        NSApp.terminate(nil)
    }
}

// MARK: - Settings Panel
class SettingsPanel: NSObject, NSWindowDelegate {
    var config: Config
    var onApply: (Config) -> Void
    var window: NSWindow?
    var selfRetain: SettingsPanel?

    let fonts = [
        "HelveticaNeue-Thin", "HelveticaNeue-UltraLight", "HelveticaNeue-Light",
        "HelveticaNeue", "HelveticaNeue-Medium", "HelveticaNeue-Bold",
        "AvenirNext-UltraLight", "AvenirNext-Light", "AvenirNext-Regular",
        "AvenirNext-Medium", "AvenirNext-Bold",
        "GillSans-Light", "GillSans", "GillSans-Bold",
        "Futura-Light", "Futura-Medium", "Futura-Bold",
        "Georgia", "Georgia-Bold", "Optima-Regular", "Optima-Bold",
        "Baskerville", "Baskerville-Bold", "AmericanTypewriter", "Menlo-Regular"
    ]

    var showBtns:   [NSButton]      = []
    var fontPops:   [NSPopUpButton] = []
    var sizeFields: [NSTextField]   = []
    var spaceFields:[NSTextField]   = []
    var colorBtns:  [NSButton]      = []
    var colorValues:[String]        = []
    var activeColorIndex = 0
    var xField = NSTextField()
    var yField = NSTextField()

    init(config: Config, onApply: @escaping (Config) -> Void) {
        self.config = config
        self.onApply = onApply
        self.colorValues = [config.weekday.color, config.date.color, config.time.color]
    }

    func windowWillClose(_ notification: Notification) {
        selfRetain = nil
        gSettingsPanel = nil
    }

    func show() {
        selfRetain = self
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 310),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        win.title = "ClockWidget Settings"
        win.level = .modalPanel
        win.delegate = self
        win.center()
        self.window = win
        guard let cv = win.contentView else { return }

        let colX: [CGFloat] = [12, 80, 140, 340, 394, 448]
        let colW: [CGFloat] = [60, 50, 190, 46,  46,  40]

        func lbl(_ t: String, x: CGFloat, y: CGFloat, w: CGFloat, bold: Bool = false) {
            let f = NSTextField(labelWithString: t)
            f.frame = NSRect(x: x, y: y, width: w, height: 20)
            f.font = bold ? .boldSystemFont(ofSize: 11) : .systemFont(ofSize: 12)
            cv.addSubview(f)
        }

        for (i, t) in ["Item","Show","Font","Size","Height","Color"].enumerated() {
            lbl(t, x: colX[i], y: 272, w: colW[i], bold: true)
        }

        let blks = [config.weekday, config.date, config.time]
        showBtns = []; fontPops = []; sizeFields = []; spaceFields = []; colorBtns = []

        for i in 0..<3 {
            let rowY = CGFloat(232 - i * 46)
            let blk  = blks[i]
            lbl(["Weekday","Date","Time"][i], x: colX[0], y: rowY, w: colW[0])

            let chk = NSButton(checkboxWithTitle: "", target: nil, action: nil)
            chk.state = blk.show ? .on : .off
            chk.frame = NSRect(x: colX[1]+12, y: rowY, width: 22, height: 22)
            cv.addSubview(chk); showBtns.append(chk)

            let fp = NSPopUpButton(frame: NSRect(x: colX[2], y: rowY-2, width: colW[2], height: 26), pullsDown: false)
            fonts.forEach { fp.addItem(withTitle: $0) }
            if let idx = fonts.firstIndex(of: blk.font) { fp.selectItem(at: idx) }
            cv.addSubview(fp); fontPops.append(fp)

            let sf = NSTextField(frame: NSRect(x: colX[3], y: rowY, width: colW[3], height: 22))
            sf.stringValue = String(Int(blk.size)); sf.isBezeled = true; sf.isEditable = true
            cv.addSubview(sf); sizeFields.append(sf)

            let spf = NSTextField(frame: NSRect(x: colX[4], y: rowY, width: colW[4], height: 22))
            spf.stringValue = String(Int(blk.spacing)); spf.isBezeled = true; spf.isEditable = true
            cv.addSubview(spf); spaceFields.append(spf)

            let cb = NSButton(frame: NSRect(x: colX[5]+2, y: rowY+2, width: colW[5]-4, height: 22))
            cb.title = ""; cb.tag = i; cb.target = self; cb.action = #selector(pickColor(_:))
            cb.wantsLayer = true
            cb.layer?.backgroundColor = nsColor(hex: blk.color).cgColor
            cb.layer?.cornerRadius = 3
            cv.addSubview(cb); colorBtns.append(cb)
        }

        let sep = NSBox(frame: NSRect(x: 12, y: 106, width: 556, height: 1))
        sep.boxType = .separator; cv.addSubview(sep)

        lbl("Position  X:", x: 12, y: 76, w: 90)
        xField = NSTextField(frame: NSRect(x: 104, y: 76, width: 55, height: 22))
        xField.stringValue = String(Int(config.x)); xField.isBezeled = true; xField.isEditable = true
        cv.addSubview(xField)
        lbl("Y:", x: 168, y: 76, w: 20)
        yField = NSTextField(frame: NSRect(x: 190, y: 76, width: 55, height: 22))
        yField.stringValue = String(Int(config.y)); yField.isBezeled = true; yField.isEditable = true
        cv.addSubview(yField)
        lbl("(px from bottom, neg=from top)", x: 254, y: 76, w: 280)

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelBtn.frame = NSRect(x: 390, y: 24, width: 80, height: 32); cv.addSubview(cancelBtn)
        let applyBtn = NSButton(title: "Apply", target: self, action: #selector(apply))
        applyBtn.frame = NSRect(x: 482, y: 24, width: 80, height: 32)
        applyBtn.bezelStyle = .rounded; applyBtn.keyEquivalent = "\r"; cv.addSubview(applyBtn)

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func pickColor(_ sender: NSButton) {
        activeColorIndex = sender.tag
        let panel = NSColorPanel.shared
        panel.color = nsColor(hex: colorValues[activeColorIndex])
        panel.isContinuous = false
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.orderFront(nil)
    }

    @objc func colorChanged(_ sender: NSColorPanel) {
        let i = activeColorIndex
        guard i >= 0 && i < 3 else { return }
        colorValues[i] = hexColor(sender.color)
        colorBtns[i].layer?.backgroundColor = sender.color.cgColor
    }

    @objc func cancel() { window?.close() }

    @objc func apply() {
        var blks = [config.weekday, config.date, config.time]
        for i in 0..<3 {
            blks[i].show    = showBtns[i].state == .on
            blks[i].font    = fontPops[i].titleOfSelectedItem ?? blks[i].font
            blks[i].size    = Double(sizeFields[i].stringValue)   ?? blks[i].size
            blks[i].spacing = Double(spaceFields[i].stringValue)  ?? blks[i].spacing
            blks[i].color   = colorValues[i]
        }
        var c = config
        c.weekday = blks[0]; c.date = blks[1]; c.time = blks[2]
        c.x = Double(xField.stringValue) ?? config.x
        c.y = Double(yField.stringValue) ?? config.y
        window?.close()
        onApply(c)
    }
}

// MARK: - Entry Point
let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()
