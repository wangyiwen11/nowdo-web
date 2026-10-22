import AppKit
import SwiftUI
import CryptoKit
import NowDoCore

/// Consumes only a pasteboard explicitly delivered by a drop or a system Service.
/// Never watches the general clipboard or modifies the source event.
@MainActor
final class CalendarQuickStart: NSObject {
    static let calendarTypes = ["com.apple.ical.ics", "com.apple.calendar.ics", "com.apple.ical.ics.event", "public.calendar-event", "text/calendar"].map { NSPasteboard.PasteboardType($0) }
    static let fileTypes: [NSPasteboard.PasteboardType] = [.fileURL, .init("NSFilenamesPboardType")]
    static var acceptedTypes: [NSPasteboard.PasteboardType] { calendarTypes + fileTypes + CalendarDropLoader.promiseTypes }
    let model: AppModel
    var onStarted: ((String) -> Void)?
    var onRejected: ((String) -> Void)?
    private var pendingRequest = UUID()

    init(model: AppModel) { self.model = model }

    static func accepts(_ board: NSPasteboard) -> Bool {
        board.availableType(from: acceptedTypes) != nil
    }

    @discardableResult
    func receive(_ board: NSPasteboard) -> Bool {
        let request = UUID()
        pendingRequest = request
        model.receivingCalendar = false
        // Calendar on macOS 26 sends a promised .ics, without a direct ICS flavor.
        if board.availableType(from: Self.calendarTypes + Self.fileTypes) == nil,
           CalendarDropLoader.canLoadPromise(board) {
            let previousSession = model.ledger.state.sessions.last
            let previousDemo = model.demo
            model.receivingCalendar = true
            model.message = "正在接收日历事项…"
            model.onDisplayChange?()
            CalendarDropLoader.loadPromise(board) { [weak self] result in
                guard let self, self.pendingRequest == request else { return }
                self.model.receivingCalendar = false
                self.model.onDisplayChange?()
                // A user's newer pause/switch/demo action takes precedence over a delayed file.
                guard self.model.ledger.state.sessions.last == previousSession, self.model.demo == previousDemo else {
                    self.reject("你已进行其他操作，这次拖入已取消。")
                    return
                }
                do { try self.start(CalendarSelection.parse(result.get())) }
                catch { self.reject(error.localizedDescription) }
            }
            return true
        }
        do {
            let selection = try Self.selection(from: board)
            try start(selection)
            return true
        } catch {
            reject(error.localizedDescription)
            return false
        }
    }

    @objc func startTiming(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        pendingRequest = UUID()
        model.receivingCalendar = false
        do { try start(Self.selection(from: pasteboard)) }
        catch let failure { error.pointee = failure.localizedDescription as NSString; reject(failure.localizedDescription) }
    }

    private func reject(_ detail: String) {
        model.message = "没有开始计时：\(detail)"
        model.onDisplayChange?()
        onRejected?(detail)
    }

    static func selection(from board: NSPasteboard) throws -> CalendarSelection {
        guard (board.pasteboardItems?.count ?? 0) <= 1 else { throw CalendarSelectionError.selectOneEvent }
        if let type = board.availableType(from: calendarTypes), let data = board.data(forType: type) {
            return try CalendarSelection.parse(data)
        }
        // Plain text and web links are not events. Promised files use the asynchronous path above.
        let urls: [URL]
        if let value = board.string(forType: .fileURL), let url = URL(string: value) {
            urls = [url]
        } else if let paths = board.propertyList(forType: .init("NSFilenamesPboardType")) as? [String] {
            urls = paths.map { URL(fileURLWithPath: $0) }
        } else { throw CalendarSelectionError.malformed }
        guard urls.count == 1 else { throw CalendarSelectionError.selectOneEvent }
        let url = urls[0]
        guard url.isFileURL, url.pathExtension.lowercased() == "ics" else { throw CalendarSelectionError.malformed }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw CalendarSelectionError.malformed }
        guard (values.fileSize ?? Int.max) <= 1_048_576 else { throw CalendarSelectionError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 1_048_577) ?? Data()
        return try CalendarSelection.parse(data)
    }

    func start(_ selection: CalendarSelection) throws {
        guard !model.readOnly else { throw QuickStartError.cannotSave }
        // A master RRULE does not tell us which occurrence was dragged. Do not invent its date.
        let unresolvedSeries = selection.hasRecurrence && selection.recurrenceID == nil
        let item = model.calendar.match(selection) ?? Self.snapshot(selection, at: Date())
        if model.demo { model.leaveDemo() }
        model.start(item)
        guard model.ledger.activeItemID == item.id, model.failure == nil else { throw QuickStartError.cannotSave }
        if unresolvedSeries { model.message = "已开始记录。这条重复日程未提供具体日期，本次只累计实际用时，不比较原计划。" }
        onStarted?(item.title)
    }

    static func snapshot(_ selection: CalendarSelection, at now: Date) -> WorkItem {
        let unresolved = selection.hasRecurrence && selection.recurrenceID == nil
        let occurrence = unresolved ? Calendar.current.startOfDay(for: now) : (selection.recurrenceID ?? selection.start)
        let raw = "\(selection.uid)|\(Int(occurrence.timeIntervalSince1970))|\(selection.title)|\(unresolved ? "series-unlinked" : "occurrence")"
        let key = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        return WorkItem(id: "calendar-drop|\(key)", title: selection.title,
                        calendarName: unresolved ? "日历传入 · 日期未关联" : "日历传入",
                        plannedStart: unresolved ? nil : selection.start,
                        plannedDuration: unresolved || selection.isAllDay ? nil : selection.end.map { $0.timeIntervalSince(selection.start) },
                        isAllDay: selection.isAllDay, createdAt: now)
    }
}

private enum QuickStartError: LocalizedError {
    case cannotSave
    var errorDescription: String? { "暂时无法保存计时，请展开计时点检查保存提示。" }
}

/// Native target keeps the drag operation copy-only; Calendar must not move the event.
@MainActor
class CalendarDropView: NSView {
    var quickStart: CalendarQuickStart?
    var hovering = false { didSet { needsDisplay = true } }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(CalendarQuickStart.acceptedTypes)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let canCopy = sender.draggingSourceOperationMask.contains(.copy)
        hovering = canCopy && CalendarQuickStart.accepts(sender.draggingPasteboard)
        return hovering ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { hovering = false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { hovering }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hovering = false
        return quickStart?.receive(sender.draggingPasteboard) ?? false
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { hovering = false }
}

@MainActor
final class CalendarDropStrip: CalendarDropView {
    override func draw(_ dirtyRect: NSRect) {
        let color = NSColor(srgbRed: 0.45, green: 0.26, blue: 0.76, alpha: 1)
        color.withAlphaComponent(hovering ? 0.18 : 0.07).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        let text = hovering ? "松手，立即开始计时" : "把苹果日历里的事项拖到这里，直接开始"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}

struct CalendarDropTarget: NSViewRepresentable {
    let quickStart: CalendarQuickStart
    func makeNSView(context: Context) -> CalendarDropStrip {
        let view = CalendarDropStrip(frame: .zero)
        view.quickStart = quickStart
        view.setAccessibilityElement(true)
        view.setAccessibilityLabel("日历计时入口：将一条日程拖到这里，立即开始")
        return view
    }
    func updateNSView(_ nsView: CalendarDropStrip, context: Context) { nsView.quickStart = quickStart }
}
