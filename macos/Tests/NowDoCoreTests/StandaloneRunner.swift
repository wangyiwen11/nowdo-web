// The Command Line Tools SDK does not ship XCTest. This conditional runner
// executes the same test methods without adding a dependency to the app.
#if STANDALONE_CORE_TESTS
import Foundation

private var assertionFailures = 0

class XCTestCase {
    private var teardowns: [() throws -> Void] = []
    func addTeardownBlock(_ block: @escaping () throws -> Void) { teardowns.append(block) }
    func runTeardowns() {
        for block in teardowns.reversed() {
            do { try block() } catch { recordFailure("Test cleanup failed: \(error)") }
        }
        teardowns.removeAll()
    }
}

private func recordFailure(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    assertionFailures += 1
    fputs("FAIL \(file):\(line) \(message)\n", stderr)
}

func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T,
                                 _ rhs: @autoclosure () throws -> T,
                                 _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let left = try lhs()
        let right = try rhs()
        if left != right { recordFailure("\(left) != \(right). \(message)", file: file, line: line) }
    } catch { recordFailure("Comparison threw: \(error). \(message)", file: file, line: line) }
}

func XCTAssertTrue(_ expression: @autoclosure () -> Bool, _ message: String = "",
                   file: StaticString = #filePath, line: UInt = #line) {
    if !expression() { recordFailure("Expected true. \(message)", file: file, line: line) }
}

func XCTAssertFalse(_ expression: @autoclosure () -> Bool, _ message: String = "",
                    file: StaticString = #filePath, line: UInt = #line) {
    if expression() { recordFailure("Expected false. \(message)", file: file, line: line) }
}

func XCTAssertNil<T>(_ expression: @autoclosure () -> T?, _ message: String = "",
                     file: StaticString = #filePath, line: UInt = #line) {
    if expression() != nil { recordFailure("Expected nil. \(message)", file: file, line: line) }
}

func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
    do {
        _ = try expression()
        recordFailure("Expected an error. \(message)", file: file, line: line)
    } catch {}
}

@main
struct StandaloneRunner {
    static func main() {
        let tests: [(String, (TimerLedgerTests) throws -> Void)] = [
            ("pause / resume / switch", { try $0.testPauseResumeAndSwitchCountOnlyWorkedTime() }),
            ("crash recovery checkpoint", { try $0.testCrashRecoveryStopsAtHeartbeatAndPersistsRepair() }),
            ("clock rewind recovery", { try $0.testRecoveryWithClockRewindNeverCreatesNegativeTime() }),
            ("midnight daily overlap", { try $0.testDailySummariesSplitAtCalendarMidnight() }),
            ("all-day plan", { try $0.testAllDayItemDoesNotAssumeTwentyFourHoursOfWork() }),
            ("corrupt file preservation", { try $0.testCorruptFileIsNeverOverwritten() }),
            ("write failure transaction", { try $0.testWriteFailureLeavesRunningStateUnchanged() }),
            ("trim bounds and notes", { try $0.testNotesAndTrimSurviveRestartWithoutOverlap() }),
            ("backwards clock transition", { try $0.testBackwardsClockDoesNotMutateOrDoubleCount() }),
            ("CSV formula and quoting", { try $0.testCSVNeutralizesFormulasAndEscapesQuotesCommasAndNewlines() }),
            ("live read-only summary", { try $0.testActiveSessionCanBeSummarizedWithoutChangingSavedData() }),
            ("original plan snapshot", { try $0.testResumingPreservesOriginalPlanForHonestReview() }),
            ("restorable backup", { try $0.testBackupUsesRestorableDiskFormat() })
        ]
        var passed = 0
        for (name, run) in tests {
            let before = assertionFailures
            let test = TimerLedgerTests()
            do { try run(test) } catch { recordFailure("\(name): \(error)") }
            test.runTeardowns()
            if assertionFailures == before {
                passed += 1
                print("PASS \(name)")
            }
        }
        print("\(passed)/\(tests.count) core scenarios passed")
        exit(assertionFailures == 0 ? 0 : 1)
    }
}
#endif
