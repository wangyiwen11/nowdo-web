#if STANDALONE_CORE_TESTS
import Foundation
#else
import XCTest
@testable import NowDoCore
#endif

final class TimerLedgerTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_792_627_200)

    private func date(_ seconds: TimeInterval) -> Date { origin.addingTimeInterval(seconds) }
    private func item(_ id: String = "a", title: String = "写作") -> WorkItem {
        WorkItem(id: id, title: title, calendarName: "工作", plannedStart: origin, plannedDuration: 3_600, createdAt: origin)
    }
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NowDoCoreTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testPauseResumeAndSwitchCountOnlyWorkedTime() throws {
        let ledger = try TimerLedger(now: origin)
        try ledger.start(item: item(), at: date(0))
        try ledger.start(item: item(), at: date(10))
        XCTAssertEqual(ledger.state.sessions.count, 1, "A second click on the same start action must not create a duplicate segment")
        try ledger.pause(at: date(60))
        try ledger.start(item: item(), at: date(180))
        try ledger.start(item: item("b", title: "开会"), at: date(240))
        try ledger.pause(at: date(300))
        XCTAssertEqual(ledger.seconds(for: "a", at: date(1_000)), 120)
        XCTAssertEqual(ledger.seconds(for: "b", at: date(1_000)), 60)
        XCTAssertEqual(ledger.state.sessions.filter { $0.end == nil }.count, 0)
        XCTAssertEqual(ledger.state.sessions[1].stopReason, "switched")
        XCTAssertNil(ledger.activeItemID)
    }

    func testCrashRecoveryStopsAtHeartbeatAndPersistsRepair() throws {
        let url = try temporaryDirectory().appendingPathComponent("nested/ledger.json")
        let first = try TimerLedger(fileURL: url, now: origin)
        try first.start(item: item(), at: date(0))
        try first.checkpoint(at: date(45))
        let recovered = try TimerLedger(fileURL: url, now: date(3_600))
        XCTAssertTrue(recovered.recoveredSession)
        XCTAssertNil(recovered.activeItemID)
        XCTAssertEqual(recovered.seconds(for: "a", at: date(3_600)), 45)
        XCTAssertEqual(recovered.state.sessions.first?.stopReason, "recovered")
        let reopened = try TimerLedger(fileURL: url, now: date(7_200))
        XCTAssertFalse(reopened.recoveredSession)
        XCTAssertEqual(reopened.seconds(for: "a", at: date(7_200)), 45)
    }

    func testRecoveryWithClockRewindNeverCreatesNegativeTime() throws {
        let url = try temporaryDirectory().appendingPathComponent("ledger.json")
        let first = try TimerLedger(fileURL: url, now: origin)
        try first.start(item: item(), at: date(100))
        try first.checkpoint(at: date(120))
        let recovered = try TimerLedger(fileURL: url, now: date(50))
        XCTAssertEqual(recovered.seconds(for: "a", at: date(50)), 0)
        XCTAssertNil(recovered.activeItemID)
    }

    func testDailySummariesSplitAtCalendarMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!
        let ledger = try TimerLedger(now: midnight)
        try ledger.start(item: item(), at: midnight.addingTimeInterval(-600))
        try ledger.pause(at: midnight.addingTimeInterval(1_200))
        let yesterday = DateInterval(start: midnight.addingTimeInterval(-86_400), end: midnight)
        let today = DateInterval(start: midnight, end: midnight.addingTimeInterval(86_400))
        XCTAssertEqual(ledger.seconds(for: "a", in: yesterday, at: midnight), 600)
        XCTAssertEqual(ledger.seconds(for: "a", in: today, at: midnight), 1_200)
        XCTAssertEqual(ledger.seconds(for: "a", at: midnight), 1_800)
        let csv = ledger.exportCSV(in: today, at: midnight)
        XCTAssertTrue(csv.contains("\"20.00\""), "Export must also clip to the selected day")
    }

    func testAllDayItemDoesNotAssumeTwentyFourHoursOfWork() throws {
        let allDay = WorkItem(id: "a", title: "整理资料", plannedDuration: 86_400, isAllDay: true, createdAt: origin)
        XCTAssertNil(allDay.plannedDuration)
        let ledger = try TimerLedger(now: origin)
        try ledger.start(item: allDay, at: origin)
        try ledger.pause(at: date(600))
        XCTAssertFalse(ledger.exportCSV(at: date(600)).contains("1440.00"))
        XCTAssertEqual(ledger.seconds(for: "a", at: date(600)), 600)
    }

    func testCorruptFileIsNeverOverwritten() throws {
        let url = try temporaryDirectory().appendingPathComponent("ledger.json")
        let original = Data("{ this is not valid JSON".utf8)
        try original.write(to: url)
        XCTAssertThrowsError(try TimerLedger(fileURL: url, now: origin))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testWriteFailureLeavesRunningStateUnchanged() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("ledger.json")
        let ledger = try TimerLedger(fileURL: url, now: origin)
        try ledger.start(item: item(), at: origin)
        let before = ledger.state
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        try Data("keep".utf8).write(to: url.appendingPathComponent("blocker"))
        XCTAssertThrowsError(try ledger.pause(at: date(60)))
        XCTAssertEqual(ledger.state, before)
        XCTAssertEqual(ledger.activeItemID, "a")
    }

    func testNotesAndTrimSurviveRestartWithoutOverlap() throws {
        let url = try temporaryDirectory().appendingPathComponent("ledger.json")
        let ledger = try TimerLedger(fileURL: url, now: origin)
        try ledger.start(item: item(), at: date(0))
        let sessionID = ledger.state.sessions[0].id
        XCTAssertThrowsError(try ledger.trimSession(sessionID: sessionID, end: date(30)))
        try ledger.start(item: item("b"), at: date(120))
        try ledger.pause(at: date(180))
        XCTAssertThrowsError(try ledger.trimSession(sessionID: sessionID, end: date(-1)))
        XCTAssertThrowsError(try ledger.trimSession(sessionID: sessionID, end: date(150)))
        try ledger.trimSession(sessionID: sessionID, end: date(90))
        try ledger.setNote(sessionID: sessionID, note: "中途被电话打断")
        let reopened = try TimerLedger(fileURL: url, now: date(200))
        XCTAssertEqual(reopened.seconds(for: "a", at: date(200)), 90)
        XCTAssertEqual(reopened.seconds(for: "b", at: date(200)), 60)
        XCTAssertEqual(reopened.state.sessions[0].note, "中途被电话打断")
    }

    func testBackwardsClockDoesNotMutateOrDoubleCount() throws {
        let ledger = try TimerLedger(now: origin)
        try ledger.start(item: item(), at: date(0))
        try ledger.checkpoint(at: date(100))
        let before = ledger.state
        XCTAssertThrowsError(try ledger.pause(at: date(50)))
        XCTAssertThrowsError(try ledger.start(item: item("b"), at: date(50)))
        XCTAssertEqual(ledger.state, before)
        try ledger.pause(at: date(120))
        XCTAssertEqual(ledger.seconds(for: "a", at: date(120)), 120)
    }

    func testCSVNeutralizesFormulasAndEscapesQuotesCommasAndNewlines() throws {
        let ledger = try TimerLedger(now: origin)
        var unsafeItem = item(title: "=HYPERLINK(\"https://example.com\",\"打开\")")
        unsafeItem.calendarName = "  @SUM(1,2)"
        try ledger.start(item: unsafeItem, at: origin)
        try ledger.pause(at: date(60))
        try ledger.setNote(sessionID: ledger.state.sessions[0].id, note: "\t+1\n含\"引号\",逗号")
        let csv = ledger.exportCSV(at: date(60))
        XCTAssertTrue(csv.contains("\"'=HYPERLINK(\"\"https://example.com\"\",\"\"打开\"\")\""))
        XCTAssertTrue(csv.contains("\"'  @SUM(1,2)\""))
        XCTAssertTrue(csv.contains("\"'\t+1\n含\"\"引号\"\",逗号\""))
        XCTAssertTrue(csv.hasSuffix("\r\n"))
    }

    func testActiveSessionCanBeSummarizedWithoutChangingSavedData() throws {
        let ledger = try TimerLedger(now: origin)
        try ledger.start(item: item(), at: origin)
        let before = ledger.state
        let interval = DateInterval(start: date(30), end: date(90))
        XCTAssertEqual(ledger.seconds(for: "a", in: interval, at: date(120)), 60)
        XCTAssertEqual(ledger.seconds(for: "a", at: date(-10)), 0)
        XCTAssertEqual(ledger.state, before)
    }

    func testResumingPreservesOriginalPlanForHonestReview() throws {
        let ledger = try TimerLedger(now: origin)
        try ledger.start(item: item(), at: origin)
        try ledger.pause(at: date(600))
        var changedCalendarItem = item(title: "写作（更新标题）")
        changedCalendarItem.plannedStart = date(600)
        changedCalendarItem.plannedDuration = 7_200
        try ledger.start(item: changedCalendarItem, at: date(900))
        XCTAssertEqual(ledger.state.items[0].plannedDuration, 3_600)
        XCTAssertEqual(ledger.state.items[0].plannedStart, origin)
        XCTAssertEqual(ledger.state.items[0].title, changedCalendarItem.title)
    }

    func testBackupUsesRestorableDiskFormat() throws {
        let ledger = try TimerLedger(now: origin)
        try ledger.start(item: item(), at: origin)
        try ledger.pause(at: date(60))
        try ledger.setNote(sessionID: ledger.state.sessions[0].id, note: "已完成")
        let url = try temporaryDirectory().appendingPathComponent("restored.json")
        try ledger.backupData().write(to: url)
        let restored = try TimerLedger(fileURL: url, now: date(120))
        XCTAssertEqual(restored.state, ledger.state)
        XCTAssertFalse(restored.recoveredSession)
    }
}
