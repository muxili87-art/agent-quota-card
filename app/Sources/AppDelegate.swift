import AppKit
import Carbon.HIToolbox
import SwiftUI

func debugLog(_ message: String) {
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("AgentQuotaCard", isDirectory: true)
    guard let directory else { return }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("debug.log")
    let line = "\(Date()) \(message)\n"
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? Data(line.utf8).write(to: url)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let ring: CGFloat = 0
    private static let originKey = "cardOrigin"
    private static let topKey = "alwaysOnTop"
    private static let intervalKey = "refreshIntervalSeconds"
    private static let currencyKey = "usageCurrency"

    private let model = StatusModel()
    private let web = WebCardController()
    private let defaults = UserDefaults.standard

    private var panel: CardPanel!
    private var surface: CardSurfaceView!
    private var cardContainer: NSView!
    private var cardSize = NSSize(width: 254, height: 122)
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var refreshTimer: Timer?
    private var watchdogTimer: Timer?
    private var hotKeyRef: EventHotKeyRef?
    private var activityToken: NSObjectProtocol?

    private var codexStartedAt: Date?
    private var agyStartedAt: Date?
    private var codexSuccessAt: Date?
    private var agySuccessAt: Date?
    private var agyBackoffUntil: Date?
    private var wakeRefreshWork: DispatchWorkItem?

    /// TokenLens 的本地服务：卡片上的「今日用量」由它提供，随 App 一起启停。
    private var tokenLensProcess: Process?

    private func ensureTokenLens() {
        let port = URL(string: "http://127.0.0.1:7777/api/state")!
        var request = URLRequest(url: port)
        request.timeoutInterval = 1.5
        let probe = URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 { return }
            self?.startTokenLens()
        }
        probe.resume()
    }

    private func startTokenLens() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let script = home.appendingPathComponent("Documents/开发项目/06-工具类/token-lens-app/server.js")
        guard FileManager.default.fileExists(atPath: script.path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", script.path]
        process.currentDirectoryURL = script.deletingLastPathComponent()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        tokenLensProcess = process
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        web.installAssets()
        ensureTokenLens()
        model.alwaysOnTop = defaults.object(forKey: Self.topKey) as? Bool ?? true
        let savedInterval = defaults.integer(forKey: Self.intervalKey)
        model.intervalSeconds = (savedInterval == 180) ? 180 : 60
        let savedCurrency = defaults.string(forKey: Self.currencyKey)
        model.currency = (savedCurrency == "CNY") ? "CNY" : "USD"

        buildPanel()
        buildStatusItem()
        buildPopover()
        installHotKey()

        restorePosition()
        applyWindowLevel()

        web.load()
        panel.orderFrontRegardless()
        model.cardVisible = true

        refreshAll(silent: true)
        restartRefreshTimer()
        startWatchdog()

        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "保持 Agent 额度刷新"
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.screensDidWakeNotification, object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenUnlocked(_:)),
            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        tokenLensProcess?.terminate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !panel.isVisible { showCard() }
        return true
    }

    @objc private func systemDidWake(_ notification: Notification) { scheduleWakeRefresh() }
    @objc private func screenUnlocked(_ notification: Notification) { scheduleWakeRefresh() }

    private func scheduleWakeRefresh() {
        wakeRefreshWork?.cancel()
        // 唤醒后等待 Wi-Fi / 代理 / DNS 就绪，避免 agy 刚唤醒时因断网误触发网页 OAuth 登录
        agyBackoffUntil = max(agyBackoffUntil ?? .distantPast, Date().addingTimeInterval(8))
        let work = DispatchWorkItem { [weak self] in
            self?.refreshAll(silent: true)
        }
        wakeRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    // MARK: - 悬浮卡片

    private func buildPanel() {
        let initial = NSSize(width: cardSize.width + Self.ring * 2, height: cardSize.height + Self.ring * 2)
        panel = CardPanel(
            contentRect: NSRect(origin: .zero, size: initial),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.title = "Agent 额度"

        let container = NSView(frame: NSRect(origin: .zero, size: initial))
        container.wantsLayer = true
        cardContainer = container
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = 0.45
        container.layer?.shadowRadius = 16
        container.layer?.shadowOffset = CGSize(width: 0, height: -6)

        let webFrame = NSRect(x: Self.ring, y: Self.ring, width: cardSize.width, height: cardSize.height)
        web.webView.frame = webFrame
        web.webView.wantsLayer = true
        web.webView.layer?.cornerRadius = 13
        web.webView.layer?.cornerCurve = .continuous
        web.webView.layer?.masksToBounds = true
        container.addSubview(web.webView)
        updateShadowPath(webFrame)

        surface = CardSurfaceView(frame: container.bounds)
        surface.autoresizingMask = [.width, .height]
        surface.onDragMove = { [weak self] rawOrigin in self?.moveCardClamped(rawOrigin) }
        surface.onDragEnd = { [weak self] in self?.clampAndSavePosition() }
        surface.onOpenDashboard = { [weak self] in self?.openDashboard() }
        surface.menuProvider = { [weak self] in self?.makeContextMenu() ?? NSMenu() }
        container.addSubview(surface)

        web.onCardSize = { [weak self] size in self?.resizeCard(to: size) }
        panel.contentView = container
    }

    private func resizeCard(to size: CGSize) {
        let rounded = NSSize(width: ceil(size.width), height: ceil(size.height))
        guard rounded.width > 80, rounded.height > 40, rounded != cardSize else { return }
        let oldFrame = panel.frame
        cardSize = rounded
        let total = NSSize(width: rounded.width + Self.ring * 2, height: rounded.height + Self.ring * 2)
        var newOrigin = NSPoint(x: oldFrame.origin.x, y: oldFrame.maxY - total.height)
        if let visible = (panel.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            newOrigin = CardGeometry.clampedOrigin(newOrigin, size: total, in: visible, ring: Self.ring)
        }
        panel.setFrame(NSRect(origin: newOrigin, size: total), display: true)
        let webFrame = NSRect(x: Self.ring, y: Self.ring, width: rounded.width, height: rounded.height)
        web.webView.frame = webFrame
        updateShadowPath(webFrame)
        surface.frame = NSRect(origin: .zero, size: total)
        defaults.set(NSStringFromPoint(panel.frame.origin), forKey: Self.originKey)
    }

    private func updateShadowPath(_ rect: NSRect) {
        cardContainer?.layer?.shadowPath =
            CGPath(roundedRect: rect, cornerWidth: 13, cornerHeight: 13, transform: nil)
    }

    private func applyWindowLevel() {
        panel.level = model.alwaysOnTop ? .floating : .normal
    }

    private func restorePosition() {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        if let saved = defaults.string(forKey: Self.originKey) {
            let point = NSPointFromString(saved)
            if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(NSRect(origin: point, size: panel.frame.size)) }) {
                let clamped = CardGeometry.clampedOrigin(point, size: panel.frame.size, in: screen.visibleFrame, ring: Self.ring)
                panel.setFrameOrigin(clamped)
                return
            }
        }
        let origin = CardGeometry.cornerOrigin(.topRight, size: panel.frame.size, in: visible, ring: Self.ring)
        panel.setFrameOrigin(origin)
    }

    private func activeScreenForDrag() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? panel.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func moveCardClamped(_ rawOrigin: NSPoint) {
        if let visible = activeScreenForDrag()?.visibleFrame {
            let clamped = CardGeometry.clampedOrigin(rawOrigin, size: panel.frame.size, in: visible, ring: Self.ring)
            panel.setFrameOrigin(clamped)
        } else {
            panel.setFrameOrigin(rawOrigin)
        }
    }

    private func clampAndSavePosition() {
        var targetOrigin = panel.frame.origin
        if let visible = activeScreenForDrag()?.visibleFrame {
            let clamped = CardGeometry.clampedOrigin(targetOrigin, size: panel.frame.size, in: visible, ring: Self.ring)
            if clamped != targetOrigin {
                targetOrigin = clamped
                panel.setFrameOrigin(clamped)
            }
        }
        defaults.set(NSStringFromPoint(targetOrigin), forKey: Self.originKey)
    }

    private func moveToCorner(_ corner: CardGeometry.Corner) {
        guard let visible = (panel.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        let target = CardGeometry.cornerOrigin(corner, size: panel.frame.size, in: visible, ring: Self.ring)
        panel.setFrame(NSRect(origin: target, size: panel.frame.size), display: true, animate: true)
        defaults.set(NSStringFromPoint(target), forKey: Self.originKey)
    }

    // MARK: - 菜单栏

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let c5 = model.codexState.fiveHour.map { max(0, min(100, Int($0.remainingPercent.rounded()))) }
        let g5 = model.agyState.fiveHour.map { max(0, min(100, Int($0.remainingPercent.rounded()))) }

        let cText = c5.map { "C \($0)" } ?? "C —"
        let gText = g5.map { "G \($0)" } ?? "G —"
        let text = "\(cText) · \(gText)"

        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let attributed = NSMutableAttributedString()
        attributed.append(statusSegment(cText, remaining: c5, font: font))
        attributed.append(NSAttributedString(string: " · ", attributes: [.font: font]))
        attributed.append(statusSegment(gText, remaining: g5, font: font))

        button.attributedTitle = attributed
        button.toolTip = "Agent 额度 · \(text)（⌃⌥Q 显示/隐藏）"
    }

    private func statusSegment(_ text: String, remaining: Int?, font: NSFont) -> NSAttributedString {
        let tier = remaining.map { Palette.tier(forRemaining: Double($0)) } ?? .ok
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        switch tier {
        case .ok: break
        case .warn: attributes[.foregroundColor] = NSColor.systemOrange
        case .crit: attributes[.foregroundColor] = NSColor.systemRed
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    private func buildPopover() {
        let view = MenuCardView(
            model: model,
            onToggleCard: { [weak self] in self?.toggleCardFromPopover() },
            onToggleInterval: { [weak self] in self?.toggleInterval() },
            onRefresh: { [weak self] in self?.refreshAll(silent: false) },
            onQuit: { NSApp.terminate(nil) }
        )
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: view)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let anchor = statusItemAnchor() ?? .zero
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.positioningRect = anchor
        refreshAll(silent: true)
    }

    private func statusItemAnchor() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let rect = button.convert(button.bounds, to: nil)
        return window.convertToScreen(rect)
    }

    private func toggleCardFromPopover() {
        panel.isVisible ? hideCard() : showCard()
        popover.performClose(nil)
    }

    func toggleCard() { panel.isVisible ? hideCard() : showCard() }

    private func showCard() {
        panel.orderFrontRegardless()
        model.cardVisible = true
        refreshAll(silent: true)
    }

    private func hideCard() {
        panel.orderOut(nil)
        model.cardVisible = false
    }

    private func setAlwaysOnTop(_ value: Bool) {
        model.alwaysOnTop = value
        defaults.set(value, forKey: Self.topKey)
        applyWindowLevel()
    }

    private func toggleInterval() {
        setInterval(model.intervalSeconds == 60 ? 180 : 60)
    }

    private func setInterval(_ seconds: Int) {
        model.intervalSeconds = seconds
        defaults.set(seconds, forKey: Self.intervalKey)
        restartRefreshTimer()
        persistAndReload()
    }

    private func setCurrency(_ currency: String) {
        model.currency = (currency == "CNY") ? "CNY" : "USD"
        defaults.set(model.currency, forKey: Self.currencyKey)
        persistAndReload()
    }

    // MARK: - 全局快捷键 ⌃⌥Q

    private func installHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { delegate.toggleCard() }
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
        let identifier = EventHotKeyID(signature: OSType(0x4147_5155), id: 1) // "AGQU"
        RegisterEventHotKey(
            UInt32(kVK_ANSI_Q),
            UInt32(controlKey | optionKey),
            identifier,
            GetApplicationEventTarget(),
            0, &hotKeyRef
        )
    }

    // MARK: - 双引擎独立并发刷新

    func refreshAll(silent: Bool) {
        refreshCodex(silent: silent)
        refreshAntigravity(silent: silent)
    }

    private func refreshCodex(silent: Bool) {
        let now = Date()
        if model.codexRefreshing {
            if let started = codexStartedAt, now.timeIntervalSince(started) > 25 {
                model.codexRefreshing = false
            } else { return }
        }
        model.codexRefreshing = true
        codexStartedAt = now

        DispatchQueue.global(qos: .utility).async {
            let outcome = Result { try CodexQuotaReader.readCurrent() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.model.codexRefreshing = false
                switch outcome {
                case let .success(state):
                    self.model.codexState = state
                    self.model.codexError = nil
                    self.model.codexUpdatedAt = Date()
                    self.codexSuccessAt = Date()
                    self.persistAndReload()
                    self.updateStatusItem()
                case let .failure(error):
                    let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.model.codexError = silent ? (self.model.codexError ?? msg) : msg
                    debugLog("codex failed: \(msg)")
                }
            }
        }
    }

    private func refreshAntigravity(silent: Bool) {
        let now = Date()
        if silent, let until = agyBackoffUntil, now < until {
            return
        }
        if model.agyRefreshing {
            if let started = agyStartedAt, now.timeIntervalSince(started) > 50 {
                model.agyRefreshing = false
            } else { return }
        }
        model.agyRefreshing = true
        agyStartedAt = now

        DispatchQueue.global(qos: .utility).async {
            let outcome = Result { try AntigravityQuotaReader.readCurrent() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.model.agyRefreshing = false
                switch outcome {
                case let .success(state):
                    self.agyBackoffUntil = nil
                    self.model.agyState = state
                    self.model.agyError = nil
                    self.model.agyUpdatedAt = Date()
                    self.agySuccessAt = Date()
                    self.persistAndReload()
                    self.updateStatusItem()
                case let .failure(error):
                    self.agyBackoffUntil = Date().addingTimeInterval(600)
                    let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.model.agyError = silent ? (self.model.agyError ?? msg) : msg
                    debugLog("agy failed: \(msg)")
                }
            }
        }
    }

    private func persistAndReload() {
        guard let data = QuotaPayload.data(
            codex: model.codexState,
            codexFetchedAt: model.codexUpdatedAt,
            antigravity: model.agyState,
            antigravityFetchedAt: model.agyUpdatedAt,
            intervalSeconds: model.intervalSeconds,
            currency: model.currency
        ) else { return }
        try? data.write(to: web.dataURL, options: .atomic)
        if let json = QuotaPayload.jsonString(
            codex: model.codexState,
            codexFetchedAt: model.codexUpdatedAt,
            antigravity: model.agyState,
            antigravityFetchedAt: model.agyUpdatedAt,
            intervalSeconds: model.intervalSeconds,
            currency: model.currency
        ) {
            web.updateQuota(json: json)
        }
    }

    // MARK: - 定时器

    private func restartRefreshTimer() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(model.intervalSeconds)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshAll(silent: true)
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func startWatchdog() {
        let watchdog = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            let limit = TimeInterval(self.model.intervalSeconds * 2)
            if now.timeIntervalSince(self.codexSuccessAt ?? .distantPast) > limit {
                self.refreshCodex(silent: true)
            }
            if now.timeIntervalSince(self.agySuccessAt ?? .distantPast) > limit {
                self.refreshAntigravity(silent: true)
            }
        }
        watchdog.tolerance = 5
        RunLoop.main.add(watchdog, forMode: .common)
        watchdogTimer = watchdog
    }

    // MARK: - 右键菜单

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: panel.isVisible ? "隐藏卡片" : "显示卡片",
            action: #selector(menuToggleCard), keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let topItem = NSMenuItem(
            title: "置顶显示",
            action: #selector(menuToggleTop), keyEquivalent: ""
        )
        topItem.target = self
        topItem.state = model.alwaysOnTop ? .on : .off
        menu.addItem(topItem)

        let cornerMenu = NSMenu()
        for (title, action) in [
            ("左上角", #selector(menuCornerTopLeft)),
            ("右上角", #selector(menuCornerTopRight)),
            ("左下角", #selector(menuCornerBottomLeft)),
            ("右下角", #selector(menuCornerBottomRight)),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            cornerMenu.addItem(item)
        }
        let cornerItem = NSMenuItem(title: "贴靠角落", action: nil, keyEquivalent: "")
        cornerItem.submenu = cornerMenu
        menu.addItem(cornerItem)

        menu.addItem(.separator())

        let int60 = NSMenuItem(title: "每 1 分钟刷新", action: #selector(menuInterval60), keyEquivalent: "")
        int60.target = self
        int60.state = model.intervalSeconds == 60 ? .on : .off
        menu.addItem(int60)

        let int180 = NSMenuItem(title: "每 3 分钟刷新", action: #selector(menuInterval180), keyEquivalent: "")
        int180.target = self
        int180.state = model.intervalSeconds == 180 ? .on : .off
        menu.addItem(int180)

        let currencyMenu = NSMenu()
        let usdItem = NSMenuItem(title: "美元 ($)", action: #selector(menuCurrencyUSD), keyEquivalent: "")
        usdItem.target = self
        usdItem.state = model.currency == "USD" ? .on : .off
        currencyMenu.addItem(usdItem)

        let cnyItem = NSMenuItem(title: "人民币 (¥)", action: #selector(menuCurrencyCNY), keyEquivalent: "")
        cnyItem.target = self
        cnyItem.state = model.currency == "CNY" ? .on : .off
        currencyMenu.addItem(cnyItem)

        let currencyItem = NSMenuItem(title: "费用币种", action: nil, keyEquivalent: "")
        currencyItem.submenu = currencyMenu
        menu.addItem(currencyItem)

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "立即刷新全部", action: #selector(menuRefresh), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let dashItem = NSMenuItem(title: "打开今日用量看板", action: #selector(menuOpenDashboard), keyEquivalent: "")
        dashItem.target = self
        menu.addItem(dashItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(menuQuit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func menuToggleCard() { toggleCard() }
    @objc private func menuToggleTop() { setAlwaysOnTop(!model.alwaysOnTop) }
    @objc private func menuCornerTopLeft() { moveToCorner(.topLeft) }
    @objc private func menuCornerTopRight() { moveToCorner(.topRight) }
    @objc private func menuCornerBottomLeft() { moveToCorner(.bottomLeft) }
    @objc private func menuCornerBottomRight() { moveToCorner(.bottomRight) }
    @objc private func menuInterval60() { setInterval(60) }
    @objc private func menuInterval180() { setInterval(180) }
    @objc private func menuCurrencyUSD() { setCurrency("USD") }
    @objc private func menuCurrencyCNY() { setCurrency("CNY") }
    @objc private func menuRefresh() { refreshAll(silent: false) }
    @objc private func menuOpenDashboard() { openDashboard() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    private func openDashboard() {
        if let url = URL(string: "http://127.0.0.1:7777") {
            NSWorkspace.shared.open(url)
        }
    }
}
