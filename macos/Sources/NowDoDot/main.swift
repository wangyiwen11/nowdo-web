import AppKit
import SwiftUI
import NowDoCore
import CoreGraphics

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DotView: CalendarDropView {
    let model: AppModel
    var expand: (() -> Void)?
    var didDrag: (() -> Void)?
    private var downLocation = NSPoint.zero
    private var initialOrigin = NSPoint.zero
    private var dragged = false
    init(model: AppModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 86, height: 74))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("NowDo 悬浮计时点")
        setAccessibilityHelp("将苹果日历的一条事项拖到小点立即开始；点击暂停或继续；拖动移动；右键展开")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { model.toggle(); return true }
    override func mouseDown(with event: NSEvent) {
        downLocation = NSEvent.mouseLocation
        initialOrigin = window?.frame.origin ?? .zero
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - downLocation.x, dy = mouse.y - downLocation.y
        if hypot(dx, dy) > 4 { dragged = true }
        if dragged { window?.setFrameOrigin(NSPoint(x: initialOrigin.x + dx, y: initialOrigin.y + dy)) }
    }
    override func mouseUp(with event: NSEvent) {
        if dragged { didDrag?(); return }
        let point = convert(event.locationInWindow, from: nil)
        if point.x > 61 { expand?() } else { model.toggle() }
    }
    override func rightMouseUp(with event: NSEvent) { expand?() }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let purple = NSColor(srgbRed: 0.45, green: 0.26, blue: 0.76, alpha: 1)
        let circle = NSRect(x: 5, y: 19, width: 52, height: 52)
        purple.setFill()
        NSBezierPath(ovalIn: circle).fill()
        NSColor.white.withAlphaComponent(hovering ? 0.95 : 0.28).setStroke()
        let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 4, dy: 4)); ring.lineWidth = hovering ? 3 : 1.5; ring.stroke()
        let symbol = model.receivingCalendar ? "ellipsis" : hovering ? "arrow.down" : model.isRunning ? "pause.fill" : model.current == nil ? "plus" : "play.fill"
        if let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 17, weight: .semibold)) {
            let tinted = NSImage(size: icon.size, flipped: false) { rect in
                icon.draw(in: rect)
                NSColor.white.setFill(); rect.fill(using: .sourceAtop); return true
            }
            tinted.draw(in: NSRect(x: 22, y: 36, width: 18, height: 18))
        }
        let label = model.receivingCalendar ? "正在接收" : hovering ? "松手开始" : model.failure != nil ? "保存出错" : model.current == nil ? "拖日程来" : timerText(model.currentSeconds)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold), .foregroundColor: purple]
        let size = (label as NSString).size(withAttributes: attrs)
        let textRect = NSRect(x: 31 - size.width / 2, y: 1, width: size.width + 8, height: 16)
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect: textRect.insetBy(dx: -4, dy: -1), xRadius: 7, yRadius: 7).fill()
        (label as NSString).draw(at: NSPoint(x: textRect.minX, y: 2), withAttributes: attrs)
        NSColor.windowBackgroundColor.withAlphaComponent(0.98).setFill()
        NSBezierPath(ovalIn: NSRect(x: 62, y: 35, width: 22, height: 22)).fill()
        ("›" as NSString).draw(at: NSPoint(x: 68, y: 34), withAttributes: [.font: NSFont.systemFont(ofSize: 19, weight: .medium), .foregroundColor: purple])
        toolTip = "把苹果日历的一条事项拖到小点，松手开始\n\(model.current?.title ?? "等待日程") · \(model.isRunning ? "点击暂停" : "点击继续")\n拖动小点移动位置，右键或点箭头展开"
        setAccessibilityValue("\(model.isRunning ? "计时中" : "已暂停")，\(label)")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var model: AppModel!
    var panel: FloatingPanel!
    var dot: FloatingPanel!
    var dotView: DotView!
    var status: NSStatusItem!
    var pauseMenu: NSMenuItem!
    var titleMenu: NSMenuItem!
    var quickStart: CalendarQuickStart!
    var receipt: FloatingPanel?
    var receiptDismiss: DispatchWorkItem?
    var usageDemo: UsageDemo?
    var observers: [NSObjectProtocol] = []
    var previewOutput: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-preview"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    var previewPage: Int? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--preview-page"), i + 1 < args.count, let page = Int(args[i + 1]), (0...4).contains(page) else { return nil }
        return page
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let guidedDemo = CommandLine.arguments.contains("--guided-demo")
        let preview = previewOutput != nil || guidedDemo
        model = AppModel(preview: preview)
        quickStart = CalendarQuickStart(model: model)
        model.quickStart = quickStart
        if preview, let page = previewPage {
            if page == 3 { model.leaveDemo() }
            else if page < 3 { model.tab = page }
        }
        panel = makePanel(size: NSSize(width: 420, height: 700))
        panel.title = "NowDo · 计时点"
        panel.isMovableByWindowBackground = true
        let hosting = NSHostingView(rootView: MainView(model: model, calendar: model.calendar))
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 20
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting
        panel.delegate = self

        dot = makePanel(size: NSSize(width: 86, height: 74))
        dot.title = "NowDo 悬浮计时点"
        dotView = DotView(model: model)
        dotView.quickStart = quickStart
        dotView.expand = { [weak self] in self?.expand() }
        dotView.didDrag = { [weak self] in self?.saveDotPosition() }
        dot.contentView = dotView
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let saved = UserDefaults.standard.dictionary(forKey: "dotPosition")
        let x = saved?["x"] as? Double ?? screen.maxX - 110
        let y = saved?["y"] as? Double ?? screen.midY
        dot.setFrameOrigin(clamped(NSPoint(x: x, y: y), size: dot.frame.size))
        model.onCollapse = { [weak self] in self?.collapse() }
        model.onExpand = { [weak self] in self?.expand() }
        model.onDisplayChange = { [weak self] in self?.updateStatus() }
        model.onQuit = { NSApp.terminate(nil) }
        if !preview { model.onShowDemo = { [weak self] in self?.showUsageDemo() } }
        quickStart.onStarted = { [weak self] title in
            guard let self else { return }
            self.collapse()
            self.showReceipt("正在记录 · \(title)")
        }
        quickStart.onRejected = { [weak self] detail in self?.showReceipt(detail, isError: true) }
        if !preview {
            NSApp.servicesProvider = quickStart
            createStatusItem()
            model.calendar.refresh()
            let nc = NSWorkspace.shared.notificationCenter
            observers.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.model.sleep() }
            })
            observers.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.model.calendar.refresh() }
            })
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.dot.setFrameOrigin(self.clamped(self.dot.frame.origin, size: self.dot.frame.size))
                    self.panel.setFrameOrigin(self.clamped(self.panel.frame.origin, size: self.panel.frame.size))
                }
            })
        }
        expand(activate: !preview)
        if guidedDemo {
            usageDemo = UsageDemo(app: self)
            usageDemo?.start()
        } else if !preview, CommandLine.arguments.contains("--show-dot") { collapse() }
        if let output = previewOutput {
            if previewPage == nil { runModelChecks() }
            if previewPage == 4 { collapse() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { Task { await self.renderPreview(to: output, index: self.previewPage ?? 0) } }
        }
    }

    func makePanel(size: NSSize) -> FloatingPanel {
        let p = FloatingPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.hidesOnDeactivate = false; p.isReleasedWhenClosed = false
        return p
    }
    func clamped(_ point: NSPoint, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame ?? NSScreen.main!.visibleFrame
        return NSPoint(x: max(screen.minX + 8, min(point.x, screen.maxX - size.width - 8)),
                       y: max(screen.minY + 8, min(point.y, screen.maxY - size.height - 8)))
    }
    func expand(activate: Bool = true) {
        panel.setFrameOrigin(clamped(NSPoint(x: dot.frame.maxX - panel.frame.width, y: dot.frame.maxY - panel.frame.height), size: panel.frame.size))
        dot.orderOut(nil)
        if activate { NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil) }
        else { panel.orderFrontRegardless() }
        updateStatus()
    }
    func collapse() { panel.orderOut(nil); dot.orderFrontRegardless(); updateStatus() }
    func showUsageDemo() {
        if model.isRunning { model.pause() }
        guard !model.isRunning, let executable = Bundle.main.executableURL else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--guided-demo"]
        do { try process.run(); NSApp.hide(nil) }
        catch { model.message = "演示暂时无法打开，请重新打开计时点后再试。" }
    }
    func showReceipt(_ text: String, isError: Bool = false) {
        receiptDismiss?.cancel()
        receipt?.orderOut(nil)
        let notice = makePanel(size: NSSize(width: 280, height: 76))
        notice.ignoresMouseEvents = true
        notice.contentView = NSHostingView(rootView:
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: isError ? "exclamationmark.circle" : "checkmark.circle.fill").foregroundStyle(Color.grape)
                Text(text).font(.system(size: 12, weight: .medium)).lineLimit(3)
            }.padding(15).frame(width: 280, height: 76, alignment: .leading)
                .foregroundStyle(Color.ink).background(Color.paper).clipShape(RoundedRectangle(cornerRadius: 14)))
        notice.setFrameOrigin(clamped(NSPoint(x: dot.frame.minX - 286, y: dot.frame.minY), size: notice.frame.size))
        notice.orderFrontRegardless()
        receipt = notice
        let dismiss = DispatchWorkItem { [weak self, weak notice] in
            notice?.orderOut(nil)
            if self?.receipt === notice { self?.receipt = nil }
        }
        receiptDismiss = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + (isError ? 6 : 3), execute: dismiss)
    }
    func saveDotPosition() {
        dot.setFrameOrigin(clamped(dot.frame.origin, size: dot.frame.size))
        UserDefaults.standard.set(["x": dot.frame.origin.x, "y": dot.frame.origin.y], forKey: "dotPosition")
    }
    func createStatusItem() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        titleMenu = NSMenuItem(title: "选一件事，开始记录", action: nil, keyEquivalent: "")
        menu.addItem(titleMenu)
        menu.addItem(.separator())
        menu.addItem(withTitle: "展开事项", action: #selector(showTasks), keyEquivalent: "")
        pauseMenu = menu.addItem(withTitle: "开始 / 暂停", action: #selector(toggleTimer), keyEquivalent: "")
        menu.addItem(withTitle: "查看复盘", action: #selector(showReview), keyEquivalent: "")
        menu.addItem(withTitle: "显示悬浮小点", action: #selector(showDot), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 NowDo", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
        status.menu = menu
        updateStatus()
    }
    func updateStatus() {
        dotView?.needsDisplay = true
        guard status != nil else { return }
        status.button?.title = model.isRunning ? "● \(timerText(model.currentSeconds))" : "◦ NowDo"
        status.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        status.button?.toolTip = model.current?.title ?? "NowDo · 计时点"
        pauseMenu.title = model.isRunning ? "暂停计时" : "继续计时"
        pauseMenu.isEnabled = model.current != nil && !model.readOnly
        titleMenu.title = String((model.current?.title ?? "选一件事，开始记录").prefix(35))
    }
    @objc func showTasks() { model.tab = 0; expand() }
    @objc func showReview() { model.tab = 1; expand() }
    @objc func toggleTimer() { model.toggle() }
    @objc func showDot() { collapse() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model != nil else { return .terminateNow }
        return model.prepareQuit() ? .terminateNow : .terminateCancel
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { expand(); return true }
    func windowShouldClose(_ sender: NSWindow) -> Bool { collapse(); return false }

    // Render only synthetic data for QA. No Calendar permission is requested here.
    func runModelChecks() {
        runCalendarQuickStartChecks()
        precondition(model.demo && !model.calendar.allowed)
        model.calendar.refresh()
        precondition(model.calendar.items.isEmpty)
        let fixture = model.displayItems[1]
        model.start(fixture)
        precondition(model.active?.id == fixture.id)
        precondition(model.currentNote.isEmpty)
        model.quickTitle = "  临时整理  "
        model.quickMinutes = "15"
        model.addQuick()
        precondition(model.active?.title == "临时整理" && model.active?.plannedDuration == 900)
        precondition(model.ledger.state.sessions.filter { $0.end == nil }.count == 1)
        model.sleep()
        precondition(!model.isRunning && model.ledger.state.sessions.last?.stopReason == "sleep")
        model.leaveDemo()
        precondition(model.ledger.state.sessions.isEmpty && model.calendar.items.isEmpty && !model.calendar.allowed)
        model.enterDemo()
        precondition(model.currentNote.contains("下一步"))
        print("PASS app flows: isolated demo, item switching, quick timer, sleep pause, clean demo exit")
    }

    func renderPreview(to directory: String, index: Int) async {
        let names = ["tasks", "review", "settings", "welcome", "dot"]
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let output = URL(fileURLWithPath: directory).appendingPathComponent("\(names[index]).png")
            if CGPreflightScreenCaptureAccess() {
                // Capture only this synthetic preview's window, never the desktop.
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-o", "-l", String((index == 4 ? dot! : panel!).windowNumber), output.path]
                let status: Int32 = try await withCheckedThrowingContinuation { continuation in
                    capture.terminationHandler = { process in continuation.resume(returning: process.terminationStatus) }
                    do { try capture.run() } catch { continuation.resume(throwing: error) }
                }
                guard status == 0 else { throw CocoaError(.fileWriteUnknown) }
            } else {
                let view = index == 4 ? dotView! : panel.contentView!
                view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: output)
                print("Fallback view render: window capture unavailable, inspect partial-render limitations")
            }
            print("Rendered \(names[index])")
        } catch { fputs("Preview render failed: \(error)\n", stderr) }
        guard index < 4, previewPage == nil else { NSApp.terminate(nil); return }
        if index < 2 { model.tab = index + 1 }
        else if index == 2 { model.leaveDemo(); model.tab = 0 }
        else { model.enterDemo(); collapse() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { Task { await self.renderPreview(to: directory, index: index + 1) } }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
