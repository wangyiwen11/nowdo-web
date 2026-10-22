import AppKit
import NowDoCore

/// Invoked only by --render-preview. All input is synthetic, storage is in memory,
/// and pasteboards have unique private names, never NSPasteboard.general.
@MainActor
func runCalendarQuickStartChecks() {
    let model = AppModel(preview: true)
    let entry = CalendarQuickStart(model: model)
    precondition(entry.responds(to: NSSelectorFromString("startTiming:userData:error:")))
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    var started = 0, rejected = 0
    entry.onStarted = { _ in started += 1 }
    entry.onRejected = { _ in rejected += 1 }
    let fixture = """
    BEGIN:VCALENDAR
    VERSION:2.0
    BEGIN:VEVENT
    UID:nowdo-fixture-1
    DTSTART:20261022T020000Z
    DTEND:20261022T024500Z
    SUMMARY:合成测试事项
    DESCRIPTION:这段备注不应该被保存
    END:VEVENT
    END:VCALENDAR
    """
    func load(_ text: String, type: NSPasteboard.PasteboardType = .init("com.apple.ical.ics")) {
        board.clearContents()
        board.setData(Data(text.utf8), forType: type)
    }
    load(fixture)
    precondition(entry.receive(board))
    precondition(!model.demo && !model.calendar.allowed && model.calendar.items.isEmpty)
    precondition(model.active?.title == "合成测试事项" && model.active?.plannedDuration == 2700)
    precondition(model.ledger.state.sessions.count == 1 && started == 1)
    let firstID = model.active!.id
    var sameUIDDifferentTitle = try! CalendarSelection.parse(fixture)
    sameUIDDifferentTitle.title = "另一份日历中的不同事项"
    precondition(CalendarQuickStart.snapshot(sameUIDDifferentTitle, at: Date()).id != firstID)
    precondition(entry.receive(board) && model.ledger.state.sessions.count == 1)
    model.pause()
    precondition(entry.receive(board) && model.ledger.state.sessions.count == 2 && model.active?.id == firstID)

    // Invalid or ambiguous input must not interrupt an already running timer.
    load(fixture.replacingOccurrences(of: "END:VCALENDAR", with: fixture + "\nEND:VCALENDAR"))
    precondition(!entry.receive(board) && model.active?.id == firstID)
    load("一个标题不等于日程", type: .string)
    precondition(!CalendarQuickStart.accepts(board) && !entry.receive(board) && model.active?.id == firstID)
    board.clearContents()
    let a = NSPasteboardItem(), b = NSPasteboardItem()
    a.setData(Data(fixture.utf8), forType: .init("com.apple.ical.ics"))
    b.setData(Data(fixture.utf8), forType: .init("com.apple.ical.ics"))
    board.writeObjects([a, b])
    precondition(!entry.receive(board) && model.active?.id == firstID)

    let second = fixture.replacingOccurrences(of: "fixture-1", with: "fixture-2")
    load(second)
    var serviceError: NSString?
    entry.startTiming(board, userData: nil, error: &serviceError)
    precondition(serviceError == nil && model.active?.id != firstID)
    precondition(model.ledger.state.sessions.filter { $0.end == nil }.count == 1)
    precondition(model.ledger.state.sessions[1].end != nil)
    let secondID = model.active!.id

    let series = fixture.replacingOccurrences(of: "SUMMARY:", with: "RRULE:FREQ=DAILY\nSUMMARY:")
    load(series)
    precondition(entry.receive(board) && model.active?.plannedStart == nil && model.active?.plannedDuration == nil)
    precondition(model.message?.contains("未提供具体日期") == true)
    let allDay = fixture.replacingOccurrences(of: "DTSTART:20261022T020000Z", with: "DTSTART;VALUE=DATE:20261022")
        .replacingOccurrences(of: "DTEND:20261022T024500Z", with: "DTEND;VALUE=DATE:20261023")
        .replacingOccurrences(of: "fixture-1", with: "fixture-allday")
    load(allDay)
    precondition(entry.receive(board) && model.active?.isAllDay == true && model.active?.plannedDuration == nil)
    precondition(!(String(data: try! model.ledger.backupData(), encoding: .utf8)!.contains("这段备注")))

    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nowdo-input-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("synthetic.ics")
    try! Data(second.utf8).write(to: file)
    board.clearContents(); board.writeObjects([file as NSURL])
    precondition(entry.receive(board) && model.active?.id == secondID)
    board.clearContents(); board.setPropertyList([file.path, file.path], forType: .init("NSFilenamesPboardType"))
    precondition(!entry.receive(board) && model.active?.id == secondID)
    board.clearContents(); board.setString("https://example.invalid/fixture.ics", forType: .fileURL)
    precondition(!entry.receive(board) && model.active?.id == secondID)
    load(fixture)
    model.readOnly = true
    precondition(!entry.receive(board) && model.active?.id == secondID)
    model.readOnly = false
    precondition(rejected == 6)
    precondition(model.prepareQuit())
    print("PASS quick-start integration: native ICS, resume/switch, Service selector, local ICS, invalid/multiple inputs, recurrence, all-day, no permissions or clipboard polling, privacy and write protection")
}
