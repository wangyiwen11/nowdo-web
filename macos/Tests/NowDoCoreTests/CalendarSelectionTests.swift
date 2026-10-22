#if STANDALONE_IMPORT_TESTS
import Foundation
#else
import XCTest
@testable import NowDoCore
#endif

final class CalendarSelectionTests: XCTestCase {
    private let hongKong = TimeZone(identifier: "Asia/Hong_Kong")!
    private func event(_ fields: String) -> String {
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\n\(fields)\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
    }
    private func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var basic: String { "UID:fixture-1\r\nSUMMARY:写作\r\nDTSTART:20261022T100000Z" }

    func testUTCEventAndEnd() throws {
        let result = try CalendarSelection.parse(event(basic + "\r\nDTEND:20261022T113000Z"), timeZone: hongKong)
        XCTAssertEqual(result.uid, "fixture-1")
        XCTAssertEqual(result.title, "写作")
        XCTAssertEqual(result.start, instant("2026-10-22T10:00:00Z"))
        XCTAssertEqual(result.end, instant("2026-10-22T11:30:00Z"))
        XCTAssertFalse(result.isAllDay)
        XCTAssertFalse(result.hasRecurrence)
        XCTAssertNil(result.recurrenceID)
    }

    func testQuotedTZIDAndFloatingLocalTime() throws {
        let named = try CalendarSelection.parse(event("UID:zone\r\nSUMMARY:见面\r\nDTSTART;TZID=\"Asia/Hong_Kong\":20261022T100000"))
        let floating = try CalendarSelection.parse(event("UID:local\r\nSUMMARY:见面\r\nDTSTART:20261022T100000"), timeZone: hongKong)
        XCTAssertEqual(named.start, instant("2026-10-22T02:00:00Z"))
        XCTAssertEqual(floating.start, named.start)
        XCTAssertThrowsError(try CalendarSelection.parse(event("UID:zone\r\nSUMMARY:见面\r\nDTSTART;TZID=MadeUp/Zone:20261022T100000")))
        XCTAssertThrowsError(try CalendarSelection.parse(event("UID:zone\r\nSUMMARY:见面\r\nDTSTART;TZID=Asia/Hong_Kong:20261022T100000Z")))
    }

    func testFoldedUnicodeAndEscapedSummary() throws {
        let fields = "UID:folded\r\nSUMMARY:写作与\r\n 中文复盘\\,计划\\;备份\\n路径\\\\文件\r\nDTSTART:20261022T100000Z"
        let result = try CalendarSelection.parse(event(fields))
        XCTAssertEqual(result.title, "写作与中文复盘,计划;备份\n路径\\文件")
        XCTAssertThrowsError(try CalendarSelection.parse(event(basic.replacingOccurrences(of: "写作", with: "写作\\x"))))
    }

    func testByteDataUnfoldsBeforeDecodingUTF8() throws {
        var data = Data("BEGIN:VEVENT\r\nUID:split\r\nSUMMARY:".utf8)
        let character = Array("中".utf8)
        data.append(character[0])
        data.append(contentsOf: [13, 10, 32])
        data.append(contentsOf: character.dropFirst())
        data.append(Data("文\r\nDTSTART:20261022T100000Z\r\nEND:VEVENT".utf8))
        XCTAssertNil(String(data: data, encoding: .utf8))
        let result = try CalendarSelection.parse(data)
        XCTAssertEqual(result.title, "中文")
        XCTAssertThrowsError(try CalendarSelection.parse(Data([0xFF, 0xFF])))
        XCTAssertThrowsError(try CalendarSelection.parse(Data(repeating: 65, count: 1_048_577)))
    }

    func testAlarmDoesNotOverrideEventMetadata() throws {
        let fields = basic + "\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\nSUMMARY:这是提醒标题\r\nDTSTART:20260101T000000Z\r\nTRIGGER:-PT15M\r\nEND:VALARM"
        let result = try CalendarSelection.parse(event(fields))
        XCTAssertEqual(result.title, "写作")
        XCTAssertEqual(result.start, instant("2026-10-22T10:00:00Z"))
    }

    func testAllDayHasNoInventedEnd() throws {
        let noEnd = try CalendarSelection.parse(event("UID:day\r\nSUMMARY:整理资料\r\nDTSTART;VALUE=DATE:20261022"), timeZone: hongKong)
        XCTAssertTrue(noEnd.isAllDay)
        XCTAssertNil(noEnd.end)
        XCTAssertEqual(noEnd.start, instant("2026-10-21T16:00:00Z"))
        let withEnd = try CalendarSelection.parse(event("UID:day\r\nSUMMARY:整理资料\r\nDTSTART;VALUE=DATE:20261022\r\nDTEND;VALUE=DATE:20261023"), timeZone: hongKong)
        XCTAssertTrue(withEnd.isAllDay)
        XCTAssertEqual(withEnd.end, instant("2026-10-22T16:00:00Z"))
        XCTAssertThrowsError(try CalendarSelection.parse(event("UID:day\r\nSUMMARY:整理资料\r\nDTSTART;VALUE=DATE:20261022\r\nDTEND:20261023T000000Z")))
    }

    func testDurationAndNominalDaysAcrossDST() throws {
        let timed = try CalendarSelection.parse(event(basic + "\r\nDURATION:PT1H30M"))
        XCTAssertEqual(timed.end, instant("2026-10-22T11:30:00Z"))
        let daylight = try CalendarSelection.parse(event("UID:dst\r\nSUMMARY:出行\r\nDTSTART;TZID=America/New_York:20260307T120000\r\nDURATION:P1D"))
        XCTAssertEqual(daylight.start, instant("2026-03-07T17:00:00Z"))
        XCTAssertEqual(daylight.end, instant("2026-03-08T16:00:00Z"))
        let week = try CalendarSelection.parse(event(basic + "\r\nDURATION:P1W"))
        XCTAssertEqual(week.end, instant("2026-10-29T10:00:00Z"))
    }

    func testInvalidDurationsFail() throws {
        for duration in ["P", "PT", "P1DT", "-PT1M", "P1M", "PT1.5H", "P99999999999999999999999D"] {
            XCTAssertThrowsError(try CalendarSelection.parse(event(basic + "\r\nDURATION:\(duration)")), duration)
        }
        XCTAssertThrowsError(try CalendarSelection.parse(event(basic + "\r\nDTEND:20261022T110000Z\r\nDURATION:PT1H")))
        XCTAssertThrowsError(try CalendarSelection.parse(event("UID:day\r\nSUMMARY:整理\r\nDTSTART;VALUE=DATE:20261022\r\nDURATION:PT24H")))
    }

    func testRecurrenceMetadataAndException() throws {
        let rule = try CalendarSelection.parse(event(basic + "\r\nRRULE:FREQ=WEEKLY;COUNT=3"))
        XCTAssertTrue(rule.hasRecurrence)
        let rdate = try CalendarSelection.parse(event(basic + "\r\nRDATE:20261023T100000Z\r\nRDATE:20261024T100000Z"))
        XCTAssertTrue(rdate.hasRecurrence)
        let exception = try CalendarSelection.parse(event(basic + "\r\nRECURRENCE-ID:20261022T090000Z"))
        XCTAssertTrue(exception.hasRecurrence)
        XCTAssertEqual(exception.recurrenceID, instant("2026-10-22T09:00:00Z"))
    }

    func testRejectsMultipleEventsAndReminderOnly() throws {
        let multiple = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\n\(basic)\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\n\(basic)\r\nEND:VEVENT\r\nEND:VCALENDAR"
        XCTAssertThrowsError(try CalendarSelection.parse(multiple))
        let todo = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\n\(basic)\r\nEND:VTODO\r\nEND:VCALENDAR"
        XCTAssertThrowsError(try CalendarSelection.parse(todo))
        XCTAssertThrowsError(try CalendarSelection.parse("写作 10:00–11:00"))
    }

    func testRejectsMissingAndDuplicateCriticalProperties() throws {
        for fragment in ["UID:fixture-1\r\n", "SUMMARY:写作\r\n", "\r\nDTSTART:20261022T100000Z"] {
            XCTAssertThrowsError(try CalendarSelection.parse(event(basic.replacingOccurrences(of: fragment, with: ""))))
        }
        for duplicate in ["UID:another", "SUMMARY:另一个标题", "DTSTART:20261023T100000Z"] {
            XCTAssertThrowsError(try CalendarSelection.parse(event(basic + "\r\n" + duplicate)))
        }
        XCTAssertThrowsError(try CalendarSelection.parse(event(basic.replacingOccurrences(of: "写作", with: " "))))
    }

    func testRejectsMalformedComponentsAndParameters() throws {
        let valid = event(basic)
        let malformed = [
            valid.replacingOccurrences(of: "END:VEVENT", with: "END:VTODO"),
            valid.replacingOccurrences(of: "END:VCALENDAR", with: ""),
            "SUMMARY:outside\r\n" + valid,
            valid + "BEGIN:VCALENDAR\r\nEND:VCALENDAR",
            valid.replacingOccurrences(of: "SUMMARY:写作", with: "SUMMARY;LANGUAGE=zh;LANGUAGE=en:写作"),
            valid.replacingOccurrences(of: "SUMMARY:写作", with: "SUMMARY;X-TEST=\"unfinished:写作"),
            " continued\r\n" + valid
        ]
        for text in malformed { XCTAssertThrowsError(try CalendarSelection.parse(text)) }
    }

    func testRejectsInvalidDatesAndBackwardsEnd() throws {
        for value in ["20260230T100000Z", "20260229T100000Z", "20261322T100000Z", "20261022T250000Z", "20261022T106000Z", "20261022T100060Z", "00001022T100000Z", "20261022T1000Z"] {
            XCTAssertThrowsError(try CalendarSelection.parse(event(basic.replacingOccurrences(of: "20261022T100000Z", with: value))), value)
        }
        XCTAssertThrowsError(try CalendarSelection.parse(event(basic + "\r\nDTEND:20261022T095959Z")))
        XCTAssertThrowsError(try CalendarSelection.parse(event("UID:dst-gap\r\nSUMMARY:不存在的本地时间\r\nDTSTART;TZID=America/New_York:20260308T023000")))
        let leap = try CalendarSelection.parse(event(basic.replacingOccurrences(of: "20261022T100000Z", with: "20280229T100000Z")))
        XCTAssertEqual(leap.start, instant("2028-02-29T10:00:00Z"))
    }

    func testSizeLimitCountsUTF8AndRejectsNull() throws {
        let tooLarge = event(basic + "\r\nDESCRIPTION:" + String(repeating: "中", count: 350_000))
        XCTAssertThrowsError(try CalendarSelection.parse(tooLarge))
        XCTAssertThrowsError(try CalendarSelection.parse(event(basic + "\r\nDESCRIPTION:bad\0data")))
    }

    func testBareEventAndLFInput() throws {
        let bare = "BEGIN:VEVENT\nUID:bare\nSUMMARY:快速计时\nDTSTART:20261022T100000Z\nEND:VEVENT"
        let result = try CalendarSelection.parse(bare)
        XCTAssertEqual(result.title, "快速计时")
        XCTAssertNil(result.end)
    }
}
