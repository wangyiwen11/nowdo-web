import AppKit
import SwiftUI
import NowDoCore

/// A separate, explicitly synthetic walkthrough. The caller must supply a preview AppModel.
@MainActor
final class UsageDemo: ObservableObject {
    private struct Step {
        let title: String
        let detail: String
        let symbol: String
        let duration: Int
    }

    private static let steps: [Step] = [
        Step(title: "先看小点怎么计时", detail: "接下来会自动操作一个示例事项。你可以看着它开始、暂停，再查看记录。", symbol: "hand.point.up.left", duration: 3),
        Step(title: "① 开始记录一件事", detail: "已开始“读一篇文章，留下一点想法”。数字正在累加，记录的是实际花费的时间。", symbol: "play.fill", duration: 3),
        Step(title: "② 收起，留下紫色小点", detail: "旁边的小点还在计时。你可以继续做事，不需要一直打开事项窗口。", symbol: "circle.fill", duration: 4),
        Step(title: "③ 点一下，暂停", detail: "现在已暂停，数字不再增加。离开一下或被打断时，就点一下紫点。", symbol: "pause.fill", duration: 3),
        Step(title: "④ 再点一下，继续", detail: "同一件事继续累计，不会清零，也不用重新选择。", symbol: "play.fill", duration: 4),
        Step(title: "⑤ 看实际花了多久", detail: "已暂停并打开“复盘”。找到刚才的示例事项，可以看到实际用时和分段记录。", symbol: "chart.bar.xaxis", duration: 5),
        Step(title: "演示结束", detail: "记住两个动作：点紫点暂停或继续；点小箭头展开查看复盘。", symbol: "checkmark.circle", duration: 0)
    ]

    @Published private(set) var stepIndex = 0
    @Published private(set) var remainingSeconds = 3
    @Published private(set) var liveTime = "00:00"
    private weak var app: AppDelegate?
    private var guide: FloatingPanel?
    private var ticker: Task<Void, Never>?
    private var stepStarted = Date()
    private var sample: WorkItem?

    init(app: AppDelegate) { self.app = app }

    var title: String { Self.steps[stepIndex].title }
    var detail: String { Self.steps[stepIndex].detail }
    var symbol: String { Self.steps[stepIndex].symbol }
    var finished: Bool { stepIndex == Self.steps.count - 1 }
    var progress: Double { Double(stepIndex) / Double(Self.steps.count - 1) }

    func start() {
        guard let app, app.model.demo, app.model.ledger.fileURL == nil,
              !app.model.calendar.allowed else { return }
        ticker?.cancel()
        if app.model.isRunning { app.model.pause() }
        app.model.query = ""
        sample = app.model.displayItems.first(where: { $0.id == "demo-read" }) ?? app.model.displayItems.first
        guard sample != nil else { return }

        if guide == nil {
            let panel = app.makePanel(size: NSSize(width: 334, height: 320))
            panel.title = "NowDo 使用演示 · 示例数据"
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            panel.isMovableByWindowBackground = true
            panel.contentView = NSHostingView(rootView: UsageDemoView(demo: self))
            guide = panel
        }
        showStep(0)
        positionGuide()
        guide?.orderFrontRegardless()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                guard let self, let app = self.app else { return }
                app.model.tick()
                self.liveTime = timerText(app.model.currentSeconds)
                guard !self.finished else { continue }
                let duration = Self.steps[self.stepIndex].duration
                self.remainingSeconds = max(0, duration - Int(Date().timeIntervalSince(self.stepStarted)))
                if self.remainingSeconds == 0 { self.next() }
            }
        }
    }

    func next() {
        guard !finished else { return }
        showStep(stepIndex + 1)
    }

    func close() {
        ticker?.cancel()
        ticker = nil
        guide?.orderOut(nil)
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: "com.even.nowdo-dot")
            where running.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            running.unhide()
        }
        NSApp.terminate(nil)
    }

    private func showStep(_ index: Int) {
        guard let app, let sample else { return }
        stepIndex = index
        stepStarted = Date()
        remainingSeconds = Self.steps[index].duration
        switch index {
        case 0:
            app.model.tab = 0
            app.expand(activate: false)
        case 1:
            app.model.start(sample)
        case 2:
            app.collapse()
        case 3:
            if app.model.isRunning { app.model.toggle() }
        case 4:
            if !app.model.isRunning { app.model.toggle() }
        case 5:
            if app.model.isRunning { app.model.pause() }
            app.model.tab = 1
            app.expand(activate: false)
        default:
            break
        }
        liveTime = timerText(app.model.currentSeconds)
        app.updateStatus()
        guide?.orderFrontRegardless()
    }

    private func positionGuide() {
        guard let app, let guide else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(app.panel.frame) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let left = app.panel.frame.minX - guide.frame.width - 18
        let right = app.panel.frame.maxX + 18
        let x = left >= screen.minX + 8 ? left
            : right + guide.frame.width < screen.maxX ? right : screen.minX + 10
        let y = app.panel.frame.maxY - guide.frame.height
        guide.setFrameOrigin(app.clamped(NSPoint(x: x, y: y), size: guide.frame.size))
    }
}

private struct UsageDemoView: View {
    @ObservedObject var demo: UsageDemo

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("NowDo · 使用演示").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: demo.close) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("关闭演示，不影响正式记录")
                .accessibilityLabel("关闭演示")
            }
            Text("演示数据 · 不写入正式记录")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.grape)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Color.grape.opacity(0.09), in: Capsule())
            HStack(spacing: 10) {
                Image(systemName: demo.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.grape)
                    .frame(width: 28)
                Text(demo.title).font(.system(size: 18, weight: .semibold))
            }
            Text(demo.detail).font(.system(size: 13)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(demo.stepIndex > 0 ? "示例计时  \(demo.liveTime)" : "正在准备示例事项")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Spacer()
                if !demo.finished { Text("\(demo.remainingSeconds) 秒后下一步").font(.system(size: 11)) }
            }
            .foregroundStyle(Color.secondary)
            ProgressView(value: demo.progress).tint(Color.grape)
            HStack {
                Text("这段演示不模拟苹果日历拖拽。")
                    .font(.system(size: 10)).foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Button(demo.finished ? "再演示一次" : "下一步") {
                    if demo.finished { demo.start() } else { demo.next() }
                }
                .buttonStyle(.borderedProminent).tint(Color.grape).controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 334, height: 320, alignment: .topLeading)
        .foregroundStyle(Color.ink)
        .background(Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.grape.opacity(0.18), lineWidth: 1))
    }
}
