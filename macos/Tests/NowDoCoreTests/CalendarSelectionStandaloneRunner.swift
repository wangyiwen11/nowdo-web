#if STANDALONE_IMPORT_TESTS
import Foundation

private var importAssertionFailures = 0
class XCTestCase {}

private func importFailure(_ message: String, file: StaticString, line: UInt) {
    importAssertionFailures += 1
    fputs("FAIL \(file):\(line) \(message)\n", stderr)
}

func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T,
                                  _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let left = try lhs(), right = try rhs()
        if left != right { importFailure("\(left) != \(right). \(message)", file: file, line: line) }
    } catch { importFailure("\(error). \(message)", file: file, line: line) }
}
func XCTAssertTrue(_ expression: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if !expression() { importFailure("Expected true. \(message)", file: file, line: line) }
}
func XCTAssertFalse(_ expression: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if expression() { importFailure("Expected false. \(message)", file: file, line: line) }
}
func XCTAssertNil<T>(_ expression: @autoclosure () -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if expression() != nil { importFailure("Expected nil. \(message)", file: file, line: line) }
}
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        _ = try expression()
        importFailure("Expected error. \(message)", file: file, line: line)
    } catch {}
}

@main
struct CalendarSelectionStandaloneRunner {
    static func main() {
        let tests: [(String, (CalendarSelectionTests) throws -> Void)] = [
            ("UTC event and end", { try $0.testUTCEventAndEnd() }),
            ("TZID and floating time", { try $0.testQuotedTZIDAndFloatingLocalTime() }),
            ("UTF-8 folding and text escaping", { try $0.testFoldedUnicodeAndEscapedSummary() }),
            ("folded multibyte UTF-8 data", { try $0.testByteDataUnfoldsBeforeDecodingUTF8() }),
            ("nested alarm isolation", { try $0.testAlarmDoesNotOverrideEventMetadata() }),
            ("all-day metadata", { try $0.testAllDayHasNoInventedEnd() }),
            ("duration and daylight saving", { try $0.testDurationAndNominalDaysAcrossDST() }),
            ("invalid duration rejection", { try $0.testInvalidDurationsFail() }),
            ("recurrence and exception identity", { try $0.testRecurrenceMetadataAndException() }),
            ("multiple event and reminder rejection", { try $0.testRejectsMultipleEventsAndReminderOnly() }),
            ("required and duplicate properties", { try $0.testRejectsMissingAndDuplicateCriticalProperties() }),
            ("malformed components", { try $0.testRejectsMalformedComponentsAndParameters() }),
            ("strict dates and end bounds", { try $0.testRejectsInvalidDatesAndBackwardsEnd() }),
            ("UTF-8 size bound and null rejection", { try $0.testSizeLimitCountsUTF8AndRejectsNull() }),
            ("standalone event and LF", { try $0.testBareEventAndLFInput() })
        ]
        var passed = 0
        for (name, run) in tests {
            let before = importAssertionFailures
            do { try run(CalendarSelectionTests()) }
            catch { importFailure("\(name): \(error)", file: #filePath, line: #line) }
            if before == importAssertionFailures { passed += 1; print("PASS \(name)") }
        }
        print("\(passed)/\(tests.count) calendar import scenarios passed")
        exit(importAssertionFailures == 0 ? 0 : 1)
    }
}
#endif
