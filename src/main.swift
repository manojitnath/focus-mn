// Focus MN: a focus timer and lofi radio in the menu bar.
// Clicking the menu bar time opens a panel (panel.html); Open Log and Settings open the dashboard (dashboard.html).
// The study log and the timer and radio settings are saved in ~/Library/Application Support/Focus MN.
// To keep the log somewhere else, choose a folder in Settings, or:
//   defaults write local.focusmn.app LogFolder ~/path/to/folder
import Cocoa
import WebKit
import UserNotifications
import ServiceManagement
import Carbon

// A borderless window that can still take typing (for the session topic).
final class PanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var panel: PanelWindow!
    var web: WKWebView!
    var dashWindow: NSWindow?
    var dashWeb: WKWebView?
    var rightMenu = NSMenu()
    var updateItem: NSMenuItem?
    var updateURL: URL?
    var panelHeight: CGFloat = 520
    var lastHidden = Date.distantPast
    var hotKeyRef: EventHotKeyRef?
    var island: PanelWindow!
    var islandWeb: WKWebView!
    var islandHeight: CGFloat = 165
    var currentNotice: [String: Any]?
    var lastNoticeId = -1
    let islandWidth: CGFloat = 360
    var activity: NSObjectProtocol?
    let panelWidth: CGFloat = 320
    let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    lazy var stateDir = supportDir.appendingPathComponent("Focus MN")
    var logDir: URL {
        guard let folder = UserDefaults.standard.string(forKey: "LogFolder"), !folder.isEmpty else { return stateDir }
        return URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
    }
    var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

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
        // The timer runs in the panel's page, which is hidden most of the time: keep macOS from napping the app.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Focus timer")
        buildPanel()
        buildIsland()
        buildStatusItem()
        registerHotKey()
        // A backstop for the page's own clock: tick every second even if WebKit slows the hidden page down.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.web.evaluateJavaScript("window.tick && tick()")
        }
        // Look for a newer release now and once a day.
        checkForUpdate()
        Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in self?.checkForUpdate() }
    }

    // MARK: pages

    // Both pages get the saved data before their script runs; the dashboard also gets its settings and first tab.
    func pageConfig(extra: String = "") -> WKWebViewConfiguration {
        var saved: [String: String] = [:]
        for key in ["studyradio.logs", "studyradio.state"] {
            if let text = try? String(contentsOf: fileURL(for: key), encoding: .utf8) { saved[key] = text }
        }
        let json = String(data: try! JSONSerialization.data(withJSONObject: saved), encoding: .utf8)!
        let content = WKUserContentController()
        content.add(self, name: "native")
        content.addUserScript(WKUserScript(source: "window.__NATIVE = true; window.__STORE = \(json); \(extra)",
                                           injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let config = WKWebViewConfiguration()
        config.userContentController = content
        config.mediaTypesRequiringUserActionForPlayback = []
        // Keep pages running while their window is hidden, so the timer and radio don't stop when the panel closes.
        if #available(macOS 14.0, *) { config.preferences.inactiveSchedulingPolicy = .none }
        return config
    }

    func loadPage(_ name: String, into view: WKWebView) {
        let html = Bundle.main.url(forResource: name, withExtension: "html")!
        // Served from a web address rather than a file, because YouTube's player refuses to run inside file pages.
        let page = (try? String(contentsOf: html, encoding: .utf8)) ?? ""
        view.loadHTMLString(page, baseURL: URL(string: "https://localhost/"))
    }

    func json(_ object: Any) -> String {
        String(data: (try? JSONSerialization.data(withJSONObject: object, options: .fragmentsAllowed)) ?? Data("null".utf8), encoding: .utf8) ?? "null"
    }

    // MARK: the panel

    // A frosted, rounded window that drops down from the menu bar time. It stays alive while hidden,
    // so the timer keeps ticking and the radio keeps playing.
    func buildPanel() {
        panel = PanelWindow(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let blur = NSVisualEffectView(frame: panel.contentView!.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.maskImage = roundedMask(14)
        panel.contentView = blur

        web = WKWebView(frame: blur.bounds, configuration: pageConfig())
        web.autoresizingMask = [.width, .height]
        web.setValue(false, forKey: "drawsBackground")
        web.wantsLayer = true
        web.layer?.cornerRadius = 14
        web.layer?.masksToBounds = true
        blur.addSubview(web)
        loadPage("panel", into: web)
        // Off screen until first opened; the page runs from the start so the timer and radio work.
        panel.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        panel.orderFront(nil)
        panel.orderOut(nil)
    }

    // A rounded-rectangle mask that stretches to any size.
    func roundedMask(_ r: CGFloat) -> NSImage {
        let edge = 2 * r + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.set()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }

    // Under the menu bar time, kept on screen. While open it stays put when its height changes,
    // even though the menu bar item gets wider once the time shows.
    func placePanel(recenter: Bool = true) {
        guard let button = statusItem.button, let bw = button.window else { return }
        let b = bw.convertToScreen(button.convert(button.bounds, to: nil))
        var x = recenter ? b.midX - panelWidth / 2 : panel.frame.minX
        if let visible = (bw.screen ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - panelWidth - 8)
        }
        let top = recenter ? b.minY - 6 : panel.frame.maxY
        panel.setFrame(NSRect(x: x, y: top - panelHeight, width: panelWidth, height: panelHeight), display: true)
    }

    func showPanel() {
        if !panel.isVisible { placePanel() }
        island.orderOut(nil)
        web.evaluateJavaScript("panelVisible(true)")
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
    }

    // Closing the panel hands any unanswered question to the top island.
    func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        lastHidden = Date()
        statusItem.button?.highlight(false)
        web.evaluateJavaScript("panelVisible(false)")
    }

    // MARK: the Island

    // The Island: a black, rounded box hanging from the notch at the top centre of the screen, for a finished block or break while the panel
    // is closed. It stays until answered; its buttons are handled by the panel page through noticeAction().
    func buildIsland() {
        island = PanelWindow(contentRect: NSRect(x: 0, y: 0, width: islandWidth, height: islandHeight),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        island.isOpaque = false
        island.backgroundColor = .clear
        island.hasShadow = true
        island.level = .popUpMenu
        island.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        island.isReleasedWhenClosed = false
        islandWeb = WKWebView(frame: island.contentView!.bounds, configuration: pageConfig())
        islandWeb.autoresizingMask = [.width, .height]
        islandWeb.setValue(false, forKey: "drawsBackground")
        island.contentView!.addSubview(islandWeb)
        loadPage("island", into: islandWeb)
    }

    func placeIsland() {
        guard let screen = NSScreen.main else { return }
        let f = screen.frame
        island.setFrame(NSRect(x: f.midX - islandWidth / 2, y: f.maxY - islandHeight, width: islandWidth, height: islandHeight), display: true)
    }

    func showNotice(_ notice: [String: Any]?) {
        currentNotice = notice
        guard let notice else { island.orderOut(nil); return }
        if panel.isVisible { return }   // the panel shows it itself
        // Start the Island's text below the menu bar (and the notch, where there is one).
        if let screen = NSScreen.main {
            var inset = screen.frame.maxY - screen.visibleFrame.maxY
            if #available(macOS 12.0, *) { inset = max(inset, screen.safeAreaInsets.top) }
            islandWeb.evaluateJavaScript("setTopInset(\(Int(inset.rounded())))")
        }
        islandWeb.evaluateJavaScript("setNotice(\(json(notice)))")
        placeIsland()
        let id = notice["id"] as? Int ?? 0
        if id != lastNoticeId { lastNoticeId = id; NSSound(named: "Glass")?.play() }
        if notice["input"] as? Bool ?? false {
            NSApp.activate(ignoringOtherApps: true)
            island.makeKeyAndOrderFront(nil)
        } else {
            island.orderFrontRegardless()
        }
    }

    // Clicking anywhere else closes the panel, like a menu.
    func windowDidResignKey(_ notification: Notification) {
        if (notification.object as? NSWindow) === panel { hidePanel() }
    }

    @objc func togglePanel() {
        // A click on the menu bar time first takes focus from the panel, which hides it; don't reopen it straight away.
        if panel.isVisible { hidePanel(); return }
        if Date().timeIntervalSince(lastHidden) < 0.3 { return }
        showPanel()
    }

    // MARK: messages from the pages

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if message.webView === islandWeb {
            if type == "noticeAction" {
                web.evaluateJavaScript("noticeAction(\(json(body["id"] ?? "")), \(json(body["topic"] ?? "")))")
            } else if type == "resize", let h = body["h"] as? Double, h.isFinite, h >= 60, h <= 600 {
                islandHeight = CGFloat(h)
                if island.isVisible { placeIsland() }
            }
            return
        }
        let fromDash = dashWeb != nil && message.webView === dashWeb
        switch type {
        case "store":
            if let key = body["key"] as? String, let value = body["value"] as? String {
                if fromDash && key != "studyradio.logs" { return }
                try? value.write(to: fileURL(for: key), atomically: true, encoding: .utf8)
                // Keep the other page's copy of the log in step.
                if key == "studyradio.logs" {
                    (fromDash ? web : dashWeb)?.evaluateJavaScript("window.__syncLogs && __syncLogs(\(value))")
                }
            }
        case "resize":
            if !fromDash, let h = body["h"] as? Double, h.isFinite, h >= 200, h <= 1200 {
                panelHeight = CGFloat(h)
                if panel.isVisible { placePanel(recenter: false) } else { panel.setContentSize(NSSize(width: panelWidth, height: panelHeight)) }
            }
        case "clock":
            // Running timer next to the menu bar icon; empty when no session is going.
            let text = body["text"] as? String ?? ""
            statusItem.button?.title = text.isEmpty ? "" : " " + text
        case "notice":
            if !fromDash { showNotice(body["notice"] as? [String: Any]) }
        case "showPanel":
            if !fromDash { showPanel() }
        case "hidePanel":
            hidePanel()
        case "nudge":
            if !fromDash {
                // Replace an earlier nudge instead of piling them up.
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["nudge"])
                let content = UNMutableNotificationContent()
                content.title = body["title"] as? String ?? "Start a session?"
                content.body = body["body"] as? String ?? ""
                content.categoryIdentifier = "NUDGE"
                content.sound = .default
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "nudge", content: content, trigger: nil))
            }
        case "notify":
            notify(title: body["title"] as? String ?? "Focus MN", body: body["body"] as? String ?? "")
            if body["show"] as? Bool ?? false { showPanel() }
        case "resolve":
            if let i = body["i"] as? Int, let channel = body["ch"] as? String, let match = body["match"] as? [String] {
                findLiveStream(channel: channel, match: match) { [weak self] id in
                    guard let id else { return }
                    self?.web.evaluateJavaScript("ytResolved(\(i), '\(id)')")
                }
            }
        case "openDashboard":
            openDashboard(tab: body["tab"] as? String ?? "stats")
        case "quit":
            NSApp.terminate(nil)
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
        case "setLaunchAtLogin":
            setLaunchAtLogin(body["on"] as? Bool ?? false)
        case "chooseLogFolder":
            chooseLogFolder()
        case "revealLogFolder":
            NSWorkspace.shared.activateFileViewerSelecting([fileURL(for: "studyradio.logs")])
        case "checkUpdates":
            checkForUpdate(manual: true)
        default:
            break
        }
    }

    // MARK: the dashboard

    func settingsJSON() -> String {
        json(["launchAtLogin": SMAppService.mainApp.status == .enabled,
              "logFolder": (logDir.path as NSString).abbreviatingWithTildeInPath,
              "version": version])
    }

    @objc func openDashboard(tab: String = "stats") {
        hidePanel()
        if let window = dashWindow, let view = dashWeb {
            if let text = try? String(contentsOf: fileURL(for: "studyradio.logs"), encoding: .utf8) {
                view.evaluateJavaScript("window.__syncLogs && __syncLogs(\(text))")
            }
            view.evaluateJavaScript("settingsChanged(\(settingsJSON())); showTab(\(json(tab)))")
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Focus MN"
        // The title bar takes the page's colour and stays draggable.
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.110, green: 0.110, blue: 0.118, alpha: 1)
                : NSColor(srgbRed: 0.961, green: 0.961, blue: 0.957, alpha: 1)
        }
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 520)
        let view = WKWebView(frame: window.contentView!.bounds,
                             configuration: pageConfig(extra: "window.__SETTINGS = \(settingsJSON()); window.__TAB = \(json(tab));"))
        view.autoresizingMask = [.width, .height]
        view.setValue(false, forKey: "drawsBackground")
        window.contentView!.addSubview(view)
        loadPage("dashboard", into: view)
        dashWeb = view
        dashWindow = window
        if !window.setFrameUsingName("FocusMNDashboard") { window.center() }
        window.setFrameAutosaveName("FocusMNDashboard")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func openLog() { openDashboard(tab: "stats") }
    @objc func openSettings() { openDashboard(tab: "settings") }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            notify(title: "Couldn't change Open at Login", body: error.localizedDescription)
        }
        dashWeb?.evaluateJavaScript("settingsChanged(\(settingsJSON()))")
    }

    // A new log folder gets a copy of the current log if it doesn't have one yet.
    func chooseLogFolder() {
        let open = NSOpenPanel()
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.canCreateDirectories = true
        open.prompt = "Use This Folder"
        open.message = "Choose where Focus MN keeps Study Log.json"
        NSApp.activate(ignoringOtherApps: true)
        guard open.runModal() == .OK, let folder = open.url else { return }
        let current = fileURL(for: "studyradio.logs")
        let target = folder.appendingPathComponent("Study Log.json")
        if !FileManager.default.fileExists(atPath: target.path), let data = try? Data(contentsOf: current) {
            try? data.write(to: target)
        }
        UserDefaults.standard.set(folder.path, forKey: "LogFolder")
        if let text = try? String(contentsOf: target, encoding: .utf8) {
            web.evaluateJavaScript("window.__syncLogs && __syncLogs(\(text))")
            dashWeb?.evaluateJavaScript("window.__syncLogs && __syncLogs(\(text))")
        }
        dashWeb?.evaluateJavaScript("settingsChanged(\(settingsJSON()))")
    }

    // MARK: menu bar

    // Click opens the panel; right-click (or Control-click) shows a small menu.
    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Focus MN")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .medium))
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        rightMenu.addItem(NSMenuItem(title: "Open Focus MN", action: #selector(togglePanel), keyEquivalent: ""))
        rightMenu.addItem(NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: ""))
        rightMenu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        rightMenu.addItem(.separator())
        rightMenu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesNow), keyEquivalent: ""))
        rightMenu.items.forEach { $0.target = self }
        rightMenu.addItem(NSMenuItem(title: "Quit Focus MN", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc func statusClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            hidePanel()
            statusItem.menu = rightMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePanel()
        }
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

    // Control-Option-Space starts or pauses the timer from any app. (Option-Command-Space is Finder's search.)
    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let me = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { me.web.evaluateJavaScript("start()") }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        let id = EventHotKeyID(signature: OSType(0x464D4E31), id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: notifications

    func setUpNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // The idle nudge gets a "Let's start" button (shown when you hover over the notification).
        let start = UNNotificationAction(identifier: "START", title: "Let\u{2019}s start", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: "NUDGE", actions: [start], intentIdentifiers: [])])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(title: String, body: String, url: URL? = nil, category: String? = nil, sound: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let url { content.userInfo = ["url": url.absoluteString] }
        if let category { content.categoryIdentifier = category }
        if sound { content.sound = .default }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // Show notification banners even while Focus MN is the active app.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    // Clicking an update notice opens the download page; any other opens the panel.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "START" {
            web.evaluateJavaScript("startCountUp()")   // starts counting up without opening the panel
        } else if let link = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        } else {
            showPanel()
        }
        completionHandler()
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
        if updateItem == nil {
            let menu = rightMenu
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

    @objc func openUpdate() { if let updateURL { NSWorkspace.shared.open(updateURL) } }
    @objc func checkForUpdatesNow() { checkForUpdate(manual: true) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
