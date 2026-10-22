// Focus MN: a floating desktop widget that hosts widget.html.
// The study log and the timer and radio settings are saved in ~/Library/Application Support/Focus MN.
// To keep the log somewhere else (a synced notes folder, say):
//   defaults write local.focusmn.app LogFolder ~/path/to/folder
import Cocoa
import WebKit
import UserNotifications

final class RadioWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// Invisible layer over the page: a press on any plain part of the radio drags the window,
// while presses on controls (whose rects the page reports) fall through to the page.
final class DragLayer: NSView {
    var controlRects: [CGRect] = []   // in page coordinates (top-left origin)
    var passAll = false               // true while a dialog, the station list or the log is open
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let p = convert(point, from: superview)
        guard bounds.contains(p) else { return nil }
        if passAll { return nil }
        let pagePoint = CGPoint(x: p.x, y: isFlipped ? p.y : bounds.height - p.y)
        return controlRects.contains { $0.insetBy(dx: -3, dy: -3).contains(pagePoint) } ? nil : self
    }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
        // Keep keyboard focus on the page so Space still starts and pauses.
        if let web = superview?.subviews.first(where: { $0 is WKWebView }) { window?.makeFirstResponder(web) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, UNUserNotificationCenterDelegate {
    var window: RadioWindow!
    var web: WKWebView!
    var statusItem: NSStatusItem!
    var onTopItem: NSMenuItem!
    var dragLayer: DragLayer!
    var logsWindow: NSWindow?
    var logsWeb: WKWebView?
    var timerItems: [NSMenuItem] = []
    var startItem: NSMenuItem!
    var skinItems: [NSMenuItem] = []
    var stationMenu = NSMenu()
    var radioItem: NSMenuItem!
    var stopItem: NSMenuItem!
    var updateItem: NSMenuItem?
    var updateURL: URL?
    let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    lazy var stateDir = supportDir.appendingPathComponent("Focus MN")
    var logDir: URL {
        guard let folder = UserDefaults.standard.string(forKey: "LogFolder"), !folder.isEmpty else { return stateDir }
        return URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
    }

    func fileURL(for key: String) -> URL {
        key == "studyradio.logs"
            ? logDir.appendingPathComponent("Study Log.json")
            : stateDir.appendingPathComponent(key + ".json")
    }

    // Earlier builds (called Mono FM, and before that Study Radio) kept settings elsewhere; bring them over once.
    func moveOldSettings() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: stateDir.path) else { return }
        for name in ["Mono FM", "Study Radio"] {
            let old = supportDir.appendingPathComponent(name)
            if fm.fileExists(atPath: old.path) { try? fm.copyItem(at: old, to: stateDir); return }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpNotifications()
        moveOldSettings()
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        buildMainMenu()

        let config = pageConfig(logsWindow: false)

        window = RadioWindow(contentRect: NSRect(x: 0, y: 0, width: 535, height: 470),
                             styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        let root = window.contentView!
        web = WKWebView(frame: root.bounds, configuration: config)
        web.autoresizingMask = [.width, .height]
        web.setValue(false, forKey: "drawsBackground")
        root.addSubview(web)

        dragLayer = DragLayer(frame: root.bounds)
        dragLayer.autoresizingMask = [.width, .height]
        dragLayer.passAll = true
        root.addSubview(dragLayer)

        loadPage(into: web)

        if !window.setFrameUsingName("StudyRadioWindow") { window.center() }
        window.setFrameAutosaveName("StudyRadioWindow")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        buildStatusItem()
        // Look for a newer release now and once a day.
        checkForUpdate()
        Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in self?.checkForUpdate() }
    }

    // Both windows run the same page. The saved data is handed to it before its script runs.
    func pageConfig(logsWindow: Bool) -> WKWebViewConfiguration {
        var saved: [String: String] = [:]
        for key in ["studyradio.logs", "studyradio.state"] {
            if let text = try? String(contentsOf: fileURL(for: key), encoding: .utf8) { saved[key] = text }
        }
        let json = String(data: try! JSONSerialization.data(withJSONObject: saved), encoding: .utf8)!
        let content = WKUserContentController()
        content.add(self, name: "native")
        content.addUserScript(WKUserScript(source: "window.__NATIVE = true; window.__LOGS_WINDOW = \(logsWindow); window.__STORE = \(json);",
                                           injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let config = WKWebViewConfiguration()
        config.userContentController = content
        config.mediaTypesRequiringUserActionForPlayback = []
        return config
    }

    func loadPage(into view: WKWebView) {
        let html = Bundle.main.url(forResource: "widget", withExtension: "html")!
        // Served from a web address rather than a file, because YouTube's player refuses to run inside file pages.
        let page = (try? String(contentsOf: html, encoding: .utf8)) ?? ""
        view.loadHTMLString(page, baseURL: URL(string: "https://localhost/"))
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        let fromLogs = logsWeb != nil && message.webView === logsWeb
        // Only the widget may move, resize or retitle the widget.
        if fromLogs && ["resize", "hit", "mode", "status", "skin", "clock", "notify", "stations", "station"].contains(type) { return }
        switch type {
        case "store":
            if let key = body["key"] as? String, let value = body["value"] as? String {
                if fromLogs && key != "studyradio.logs" { return }
                try? value.write(to: fileURL(for: key), atomically: true, encoding: .utf8)
                // Keep the other window's copy of the log in step.
                if key == "studyradio.logs" {
                    let other = fromLogs ? web : logsWeb
                    other?.evaluateJavaScript("window.__syncLogs && __syncLogs(\(value))")
                }
            }
        case "closeLogs":
            logsWindow?.orderOut(nil)
        case "resize":
            if let w = body["w"] as? Double, let h = body["h"] as? Double,
               w.isFinite, h.isFinite, w >= 200, h >= 120, w <= 3000, h <= 3000 {
                let lock = body["lock"] as? Bool ?? false
                // The radio keeps its shape when you drag a corner; the log window resizes freely.
                if lock {
                    window.contentAspectRatio = NSSize(width: w, height: h)
                    window.minSize = NSSize(width: 220, height: 220 * h / w)
                    window.maxSize = NSSize(width: 600, height: 600 * h / w)
                } else {
                    window.resizeIncrements = NSSize(width: 1, height: 1)
                    window.minSize = NSSize(width: 600, height: 450)
                    window.maxSize = NSSize(width: 2000, height: 2000)
                }
                resize(CGFloat(w), CGFloat(h))
            }
        case "hit":
            dragLayer.passAll = body["all"] as? Bool ?? false
            let rects = body["rects"] as? [[Double]] ?? []
            dragLayer.controlRects = rects.filter { $0.count == 4 }.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
        case "resolve":
            if let i = body["i"] as? Int, let channel = body["ch"] as? String, let match = body["match"] as? [String] {
                findLiveStream(channel: channel, match: match) { [weak self] id in
                    guard let id else { return }
                    self?.web.evaluateJavaScript("ytResolved(\(i), '\(id)')")
                }
            }
        case "notify":
            notify(title: body["title"] as? String ?? "Focus MN", body: body["body"] as? String ?? "")
            // Bring a hidden widget back so its questions can be answered.
            if body["show"] as? Bool ?? false { showWindow() }
        case "clock":
            // Running timer next to the menu bar icon; empty when no session is going.
            let text = body["text"] as? String ?? ""
            statusItem.button?.title = text.isEmpty ? "" : " " + text
        case "skin":
            // Tick the skin that is showing.
            let id = body["id"] as? String ?? ""
            for item in skinItems { item.state = (item.representedObject as? String) == id ? .on : .off }
        case "status":
            // The first menu item follows the timer: Start, Pause or Resume.
            let status = body["status"] as? String ?? "idle"
            startItem.title = status == "running" ? "Pause" : status == "paused" ? "Resume" : "Start"
            stopItem.isEnabled = status != "idle"
        case "stations":
            // The page sends its station list once, so the menu never goes out of step with it.
            let names = body["names"] as? [String] ?? []
            while stationMenu.items.count > 2 { stationMenu.removeItem(at: 2) }
            for (i, name) in names.enumerated() {
                let item = NSMenuItem(title: name, action: #selector(playStation(_:)), keyEquivalent: "")
                item.tag = i
                item.target = self
                stationMenu.addItem(item)
            }
        case "station":
            // Tick the current station; the first item turns the radio on or off.
            let i = body["i"] as? Int ?? -1, on = body["on"] as? Bool ?? false
            radioItem.title = on ? "Radio Off" : "Radio On"
            for item in stationMenu.items.dropFirst(2) { item.state = item.tag == i ? (on ? .on : .mixed) : .off }
        case "mode":
            let mode = body["mode"] as? String ?? "free"
            let minutes = body["min"] as? Int ?? 20
            for item in timerItems { item.state = (mode == "free" ? item.tag == 0 : item.tag == minutes) ? .on : .off }
        case "copy":
            if let text = body["text"] as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        case "csv":
            if let text = body["text"] as? String {
                let url = logDir.appendingPathComponent("Study Log.csv")
                try? text.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        default:
            break
        }
    }

    // Reads a channel's Live tab and returns the live stream whose title contains every match phrase.
    // YouTube lists each stream as a "lockupViewModel"; live ones show a "watching" count.
    func findLiveStream(channel: String, match: [String], done: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://www.youtube.com/@\(channel)/streams") else { return done(nil) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            var found: String?
            if let data, let page = String(data: data, encoding: .utf8),
               let start = page.range(of: "var ytInitialData = "),
               let end = page.range(of: ";</script>", range: start.upperBound..<page.endIndex),
               let json = try? JSONSerialization.jsonObject(with: Data(page[start.upperBound..<end.lowerBound].utf8)) {
                let wanted = match.map { $0.lowercased() }
                func walk(_ node: Any) {
                    if found != nil { return }
                    if let dict = node as? [String: Any] {
                        if let lockup = dict["lockupViewModel"] as? [String: Any], let id = lockup["contentId"] as? String,
                           let meta = (lockup["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any],
                           let title = ((meta["title"] as? [String: Any])?["content"] as? String)?.lowercased(),
                           let raw = try? JSONSerialization.data(withJSONObject: lockup),
                           String(decoding: raw, as: UTF8.self).contains(" watching"),
                           wanted.allSatisfy({ title.contains($0) }) {
                            found = id
                            return
                        }
                        dict.values.forEach(walk)
                    } else if let list = node as? [Any] {
                        list.forEach(walk)
                    }
                }
                walk(json)
            }
            DispatchQueue.main.async { done(found) }
        }.resume()
    }

    // macOS notifications: a heads-up only; the widget asks the questions.
    func setUpNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(title: String, body: String, url: URL? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let url { content.userInfo = ["url": url.absoluteString] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // Show banners even while Focus MN is the active app.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Clicking an update notice opens the download page; any other brings up the widget.
        if let link = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        } else {
            showWindow()
        }
        completionHandler()
    }

    // Updates: ask GitHub for the latest release and compare it with this build's version.
    // Nothing is downloaded or installed; the menu and a notification point to the release page.
    func checkForUpdate(manual: Bool = false) {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/manojitnath/focus-mn/releases/latest")!, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let release = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async { self.handleRelease(release, manual: manual) }
        }.resume()
    }

    func handleRelease(_ release: [String: Any]?, manual: Bool) {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        guard let tag = release?["tag_name"] as? String, let page = (release?["html_url"] as? String).flatMap(URL.init(string:)) else {
            if manual { notify(title: "Couldn't check for updates", body: "GitHub didn't answer. Try again later.") }
            return
        }
        let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard isVersion(latest, newerThan: current) else {
            if manual { notify(title: "Focus MN is up to date", body: "You have the latest version, \(current).") }
            return
        }
        updateURL = page
        if updateItem == nil, let menu = statusItem.menu {
            let item = NSMenuItem(title: "", action: #selector(openUpdate), keyEquivalent: "")
            item.target = self
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
            updateItem = item
        }
        updateItem?.title = "Update Available: \(latest)…"
        // Each new version is announced once; a manual check always answers.
        if manual || UserDefaults.standard.string(forKey: "NotifiedVersion") != latest {
            UserDefaults.standard.set(latest, forKey: "NotifiedVersion")
            notify(title: "Focus MN \(latest) is out", body: "Click to download it. Your log and settings are kept.", url: page)
        }
    }

    // Compares dotted versions number by number, so 1.10 is newer than 1.9.
    func isVersion(_ a: String, newerThan b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    // Resize around the window's top centre, kept on screen.
    func resize(_ w: CGFloat, _ h: CGFloat) {
        var frame = window.frame
        let top = frame.maxY, centre = frame.midX
        frame.size = NSSize(width: w, height: h)
        frame.origin = NSPoint(x: centre - w / 2, y: top - h)
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - w)
            frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - h)
        }
        window.setFrame(frame, display: true, animate: false)
    }

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "radio", accessibilityDescription: "Focus MN")
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let menu = NSMenu()
        menu.autoenablesItems = false
        startItem = NSMenuItem(title: "Start", action: #selector(startPause), keyEquivalent: "")
        stopItem = NSMenuItem(title: "Stop", action: #selector(stopTimer), keyEquivalent: "")
        stopItem.isEnabled = false
        menu.addItem(startItem)
        menu.addItem(stopItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Show or Hide Radio", action: #selector(toggleWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Logs", action: #selector(openLogs), keyEquivalent: ""))
        menu.addItem(.separator())
        radioItem = NSMenuItem(title: "Radio On", action: #selector(toggleRadio), keyEquivalent: "")
        radioItem.target = self
        stationMenu.autoenablesItems = false
        stationMenu.addItem(radioItem)
        stationMenu.addItem(.separator())
        let stationItem = NSMenuItem(title: "Station", action: nil, keyEquivalent: "")
        stationItem.submenu = stationMenu
        menu.addItem(stationItem)
        let timer = NSMenu()
        for (title, value) in [("Timer (counts up)", 0), ("Pomodoro 20 min", 20), ("Pomodoro 40 min", 40), ("Pomodoro 60 min", 60)] {
            let item = NSMenuItem(title: title, action: #selector(setTimerMode(_:)), keyEquivalent: "")
            item.tag = value
            item.target = self
            timer.addItem(item)
            timerItems.append(item)
        }
        let timerItem = NSMenuItem(title: "Timer", action: nil, keyEquivalent: "")
        timerItem.submenu = timer
        menu.addItem(timerItem)
        let sizes = NSMenu()
        for (title, width) in [("XS", 240), ("Small", 340), ("Medium", 460)] {
            let item = NSMenuItem(title: title, action: #selector(setSize(_:)), keyEquivalent: "")
            item.tag = width
            item.target = self
            sizes.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizes
        menu.addItem(sizeItem)
        let skins = NSMenu()
        for (id, title) in [("walnut", "Walnut"), ("mint", "Mint"), ("midnight", "Midnight"), ("cherry", "Cherry"),
                            ("gameboy", "FOCUS MN Pocket"), ("gameboy-dark", "FOCUS MN Pocket Dark"),
                            ("classic", "FOCUS MN Classic"), ("classic-dark", "FOCUS MN Classic Dark")] {
            let item = NSMenuItem(title: title, action: #selector(setSkin(_:)), keyEquivalent: "")
            item.representedObject = id
            item.target = self
            skins.addItem(item)
            skinItems.append(item)
        }
        let skinItem = NSMenuItem(title: "Skin", action: nil, keyEquivalent: "")
        skinItem.submenu = skins
        menu.addItem(skinItem)
        onTopItem = NSMenuItem(title: "Keep on Top", action: #selector(toggleOnTop), keyEquivalent: "")
        onTopItem.state = .on
        menu.addItem(onTopItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesNow), keyEquivalent: ""))
        menu.items.forEach { $0.target = self }
        menu.addItem(NSMenuItem(title: "Quit Focus MN", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // An Edit menu so copy and paste work in the topic field.
    func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(), editItem = NSMenuItem()
        main.addItem(appItem)
        main.addItem(editItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Focus MN", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    @objc func toggleWindow() {
        if window.isVisible { window.orderOut(nil) } else { showWindow() }
    }
    // The log opens in its own window; the widget stays where it is.
    @objc func openLogs() {
        if let window = logsWindow {
            if let text = try? String(contentsOf: fileURL(for: "studyradio.logs"), encoding: .utf8) {
                logsWeb?.evaluateJavaScript("window.__syncLogs && __syncLogs(\(text))")
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Focus MN Log"
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(red: 0.086, green: 0.075, blue: 0.122, alpha: 1)
        window.minSize = NSSize(width: 520, height: 480)
        let view = WKWebView(frame: window.contentView!.bounds, configuration: pageConfig(logsWindow: true))
        view.autoresizingMask = [.width, .height]
        view.setValue(false, forKey: "drawsBackground")
        window.contentView!.addSubview(view)
        loadPage(into: view)
        logsWeb = view
        logsWindow = window
        if !window.setFrameUsingName("FocusMNLogWindow") { window.center() }
        window.setFrameAutosaveName("FocusMNLogWindow")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func setSize(_ sender: NSMenuItem) {
        showWindow()
        web.evaluateJavaScript("setWidgetWidth(\(sender.tag))")
    }
    @objc func playStation(_ sender: NSMenuItem) { web.evaluateJavaScript("playStation(\(sender.tag))") }
    @objc func toggleRadio() { web.evaluateJavaScript("setRadio(!radioOn)") }
    @objc func startPause() { web.evaluateJavaScript("start()") }
    @objc func stopTimer() { web.evaluateJavaScript("stop()") }
    @objc func setTimerMode(_ sender: NSMenuItem) {
        web.evaluateJavaScript(sender.tag == 0 ? "setMode('free')" : "setMode('pomo', \(sender.tag))")
    }
    @objc func setSkin(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        showWindow()
        web.evaluateJavaScript("setSkin('\(id)')")
    }
    @objc func openUpdate() { if let updateURL { NSWorkspace.shared.open(updateURL) } }
    @objc func checkForUpdatesNow() { checkForUpdate(manual: true) }
    @objc func toggleOnTop() {
        window.level = window.level == .floating ? .normal : .floating
        onTopItem.state = window.level == .floating ? .on : .off
    }
    func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
