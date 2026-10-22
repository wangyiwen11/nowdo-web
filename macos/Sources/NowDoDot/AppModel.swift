import AppKit
import Combine
import NowDoCore
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var now = Date()
    @Published var revision = 0
    @Published var day = Calendar.current.startOfDay(for: Date())
    @Published var tab = 0
    @Published var query = ""
    @Published var message: String?
    @Published var failure: String?
    @Published var demo = false
    @Published var lastItemID: String?
    @Published var quickTitle = ""
    @Published var quickMinutes = ""
    @Published var showQuick = false
    @Published var receivingCalendar = false
    let calendar: CalendarBridge
    private(set) var ledger: TimerLedger
    private var realLedger: TimerLedger?
    private var ticker: Timer?
    private var ticks = 0
    private var previousTick = Date()
    private var previousUptime = ProcessInfo.processInfo.systemUptime
    var readOnly = false
    var onDisplayChange: (() -> Void)?
    var onCollapse: (() -> Void)?
    var onExpand: (() -> Void)?
    var onQuit: (() -> Void)?
    var onShowDemo: (() -> Void)?
    weak var quickStart: CalendarQuickStart?
    static var dataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NowDoDot", isDirectory: true)
    }

    init(preview: Bool = false) {
        calendar = CalendarBridge(disabled: preview)
        do {
            ledger = try TimerLedger(fileURL: preview ? nil : Self.dataDirectory.appendingPathComponent("time-records.json"))
        } catch {
            ledger = try! TimerLedger(fileURL: nil)
            readOnly = true
            failure = "记录文件无法读取，已停止写入以保留原文件。\(error.localizedDescription)"
        }
        if ledger.recoveredSession { message = "上次意外中断，计时已停在最后保存的时刻。可以在复盘中检查。" }
        lastItemID = ledger.state.sessions.last?.itemID
        if preview { enterDemo() }
        if !preview {
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
    }

    var interval: DateInterval {
        let start = Calendar.current.startOfDay(for: day)
        return DateInterval(start: start, end: Calendar.current.date(byAdding: .day, value: 1, to: start)!)
    }
    var active: WorkItem? { ledger.state.items.first { $0.id == ledger.activeItemID } }
    var current: WorkItem? { active ?? ledger.state.items.first { $0.id == lastItemID } }
    var isRunning: Bool { ledger.activeItemID != nil }
    var currentSeconds: TimeInterval { current.map { ledger.seconds(for: $0.id, in: nil, at: now) } ?? 0 }
    var currentNote: String {
        guard let current else { return "" }
        return ledger.state.sessions.last(where: { $0.itemID == current.id && !$0.note.isEmpty })?.note ?? ""
    }
    var displayItems: [WorkItem] {
        let base = demo ? demoItems : calendar.items
        return base.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.calendarName.localizedCaseInsensitiveContains(query) }
    }
    var previousItems: [WorkItem] {
        let shown = Set(displayItems.map(\.id))
        return ledger.state.items.reversed().filter { !shown.contains($0.id) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
    }
    var reviewItems: [WorkItem] {
        ledger.state.items.filter { ledger.seconds(for: $0.id, in: interval, at: now) > 0 }
            .sorted { seconds($0) > seconds($1) }
    }
    var sessions: [TimeSession] {
        ledger.state.sessions.filter { $0.start < interval.end && ($0.end ?? now) > interval.start }.reversed()
    }
    var total: TimeInterval { reviewItems.reduce(0) { $0 + seconds($1) } }
    func seconds(_ item: WorkItem) -> TimeInterval { ledger.seconds(for: item.id, in: interval, at: now) }
    func itemTitle(_ id: String) -> String { ledger.state.items.first { $0.id == id }?.title ?? "已保留的事项" }
    func allTime(_ item: WorkItem) -> TimeInterval { ledger.seconds(for: item.id, in: nil, at: now) }

    private func change(_ action: () throws -> Void) {
        guard !readOnly else { return }
        do { try action(); failure = nil; revision += 1; onDisplayChange?() }
        catch {
            let shouldReveal = failure == nil
            failure = "保存没有成功：\(error.localizedDescription)。请先保留窗口，检查磁盘空间或目录权限。"
            if shouldReveal { onExpand?() }
        }
    }
    func start(_ item: WorkItem) {
        change { try ledger.start(item: item, at: Date()) }
        if ledger.activeItemID == item.id { lastItemID = item.id; message = nil }
        now = Date()
        previousTick = now
        previousUptime = ProcessInfo.processInfo.systemUptime
    }
    func pause(reason: String = "manual") {
        change { try ledger.pause(at: Date(), reason: reason) }
        now = Date()
    }
    func toggle() {
        if isRunning { pause() }
        else if let current { start(current) }
        else { onExpand?() }
    }
    func tick() {
        let date = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        if !Calendar.current.isDate(previousTick, inSameDayAs: date), Calendar.current.isDate(day, inSameDayAs: previousTick) {
            day = Calendar.current.startOfDay(for: date)
            calendar.date = day
            if !demo { calendar.refresh() }
        }
        let wallGap = date.timeIntervalSince(previousTick)
        let steadyGap = uptime - previousUptime
        if isRunning && (wallGap > 120 || abs(wallGap - steadyGap) > 3 || wallGap < 0) {
            change { try ledger.pause(at: max(previousTick, ledger.state.lastCheckpoint ?? previousTick), reason: "interrupted") }
            if !isRunning { message = "系统时间或运行状态发生变化，已暂停。请检查这段记录。" }
        }
        now = date; previousTick = date; previousUptime = uptime
        ticks += 1
        if ticks % 15 == 0 && isRunning { change { try ledger.checkpoint(at: now) } }
        if ticks % 60 == 0 && !demo { calendar.refresh() }
        onDisplayChange?()
    }
    func shiftDay(_ amount: Int) {
        day = Calendar.current.date(byAdding: .day, value: amount, to: day)!
        calendar.date = day
        if !demo { calendar.refresh() }
    }
    func today() { day = Calendar.current.startOfDay(for: Date()); calendar.date = day; if !demo { calendar.refresh() } }
    func addQuick() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let minutes = Double(quickMinutes)
        if !quickMinutes.isEmpty && (minutes == nil || minutes! <= 0 || minutes! > 1440) {
            failure = "计划时长请填 1–1440 分钟，也可以留空。"; return
        }
        let item = WorkItem(id: "local|\(UUID().uuidString)", title: title, calendarName: "临时事项",
                            plannedStart: Date(), plannedDuration: minutes.map { $0 * 60 }, isAllDay: false, createdAt: Date())
        start(item)
        if ledger.activeItemID == item.id { quickTitle = ""; quickMinutes = ""; showQuick = false }
    }
    func saveNote(_ note: String, session: TimeSession) {
        change { try ledger.setNote(sessionID: session.id, note: note) }
    }
    func trim(_ session: TimeSession, end: Date) {
        change { try ledger.trimSession(sessionID: session.id, end: end) }
    }
    func sleep() {
        if isRunning {
            pause(reason: "sleep")
            if !isRunning { message = "Mac 休眠，计时已暂停。回来后点一下继续。" }
        }
    }
    func prepareQuit() -> Bool {
        if isRunning { pause(reason: "quit") }
        return !isRunning
    }
    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "NowDo-\(day.formatted(.iso8601.year().month().day().dateSeparator(.dash)))-复盘.csv"
        panel.message = "导出当前日期的计时记录，包含事项名称和复盘备注。"
        if panel.runModal() == .OK, let url = panel.url {
            do { try ledger.exportCSV(in: interval, at: now).write(to: url, atomically: true, encoding: .utf8); message = "当天记录已导出。" }
            catch { failure = "导出失败：\(error.localizedDescription)" }
        }
    }
    func backup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "NowDo-完整记录备份.json"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                if isRunning { try ledger.checkpoint(at: Date()) }
                try ledger.backupData().write(to: url, options: .atomic)
                message = "完整记录已备份。"
            } catch { failure = "备份失败：\(error.localizedDescription)" }
        }
    }
    private var demoItems: [WorkItem] {
        let start = Calendar.current.startOfDay(for: Date())
        return [
            WorkItem(id: "demo-write", title: "整理本周的观察", calendarName: "工作 · 示例", plannedStart: start.addingTimeInterval(36000), plannedDuration: 2700, isAllDay: false, createdAt: start),
            WorkItem(id: "demo-read", title: "读一篇文章，留下一点想法", calendarName: "学习 · 示例", plannedStart: start, plannedDuration: nil, isAllDay: true, createdAt: start),
            WorkItem(id: "demo-plan", title: "准备明天的计划", calendarName: "生活 · 示例", plannedStart: start.addingTimeInterval(64800), plannedDuration: 1200, isAllDay: false, createdAt: start)
        ]
    }
    func enterDemo() {
        guard !demo else { return }
        if isRunning { pause() }
        guard !isRunning else { return }
        realLedger = ledger
        ledger = try! TimerLedger(fileURL: nil)
        demo = true
        let sample = demoItems[0]
        let start = Date().addingTimeInterval(-1680)
        try? ledger.start(item: sample, at: start)
        try? ledger.pause(at: Date().addingTimeInterval(-180), reason: "manual")
        if let session = ledger.state.sessions.last { try? ledger.setNote(sessionID: session.id, note: "资料已整理好，下一步写开头。") }
        lastItemID = sample.id
        now = Date(); revision += 1; onDisplayChange?()
    }
    func leaveDemo() {
        guard let realLedger else { return }
        ledger = realLedger; self.realLedger = nil; demo = false
        lastItemID = ledger.state.sessions.last?.itemID
        message = nil; today(); revision += 1; onDisplayChange?()
    }
}

func timerText(_ seconds: TimeInterval) -> String {
    let t = max(0, Int(seconds))
    if t >= 3600 { return String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) }
    return String(format: "%02d:%02d", t / 60, t % 60)
}

func minuteText(_ seconds: TimeInterval) -> String {
    if seconds < 60 { return "\(max(0, Int(seconds))) 秒" }
    let mins = Int((seconds / 60).rounded())
    return mins >= 60 ? "\(mins / 60) 小时 \(mins % 60) 分" : "\(mins) 分钟"
}
