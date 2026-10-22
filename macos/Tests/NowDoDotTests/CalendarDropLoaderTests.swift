import AppKit

/// Runs separately from the app. Every pasteboard has a private unique name;
/// only temporary fixture files are used. This is not an Apple Calendar E2E test.
@main
struct CalendarDropLoaderTests {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("nowdo-loader-tests-\(UUID())")
        let directory = root.appendingPathComponent("received")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: root) }
        var passed = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            passed += 1
            print("PASS \(name)")
        }
        func rejects(_ url: URL) -> Bool {
            do { _ = try CalendarDropLoader.readFile(url, inside: directory); return false }
            catch { return true }
        }
        let fixture = Data("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:nowdo-drop-fixture\r\nDTSTART:20261022T020000Z\r\nSUMMARY:合成日程\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n".utf8)
        let valid = directory.appendingPathComponent("合成日程.ics")
        try fixture.write(to: valid)
        let loaded = try CalendarDropLoader.readFile(valid, inside: directory)
        check(loaded == fixture, "synthetic ICS bytes preserved")
        let boundary = directory.appendingPathComponent("boundary.ics")
        try Data(repeating: 65, count: 1_048_576).write(to: boundary)
        let boundaryData = try CalendarDropLoader.readFile(boundary, inside: directory)
        check(boundaryData.count == 1_048_576, "1 MB boundary accepted")
        try Data(repeating: 65, count: 1_048_577).write(to: boundary)
        check(rejects(boundary), "oversized promised file rejected")
        let outside = root.appendingPathComponent("outside.ics")
        try fixture.write(to: outside)
        check(rejects(outside), "file outside private destination rejected")
        let symlink = directory.appendingPathComponent("symlink.ics")
        try fm.createSymbolicLink(at: symlink, withDestinationURL: valid)
        check(rejects(symlink), "symbolic link rejected even with an inside target")
        let folder = directory.appendingPathComponent("folder.ics")
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        check(rejects(folder), "directory rejected")
        let wrongType = directory.appendingPathComponent("document.txt")
        try fixture.write(to: wrongType)
        check(rejects(wrongType), "non-ICS extension rejected")
        check(rejects(URL(string: "https://example.invalid/event.ics")!), "remote URL rejected without fetching")
        check(rejects(directory.appendingPathComponent("missing.ics")), "missing file rejected")

        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("synthetic", forType: .string)
        check(!CalendarDropLoader.canLoadPromise(board), "ordinary text is not a promised event")
        var rejectionCount = 0
        CalendarDropLoader.loadPromise(board) { result in
            if case .failure = result { rejectionCount += 1 }
        }
        check(rejectionCount == 1, "unsupported board fails once")

        let delegate = FixturePromiseDelegate(data: fixture)
        let first = NSFilePromiseProvider(fileType: "com.apple.ical.ics", delegate: delegate)
        let second = NSFilePromiseProvider(fileType: "com.apple.ical.ics", delegate: delegate)
        board.clearContents()
        check(board.writeObjects([first, second]), "synthetic promise metadata written")
        check(CalendarDropLoader.canLoadPromise(board), "native promise types recognized without direct ICS")
        CalendarDropLoader.loadPromise(board) { result in
            if case .failure = result { rejectionCount += 1 }
        }
        check(rejectionCount == 2, "multiple promised items rejected before receiving")

        // Private pasteboards do not provide a live drag session. This exercises
        // the terminal callback and temporary-directory cleanup, not Calendar delivery.
        board.clearContents()
        check(board.writeObjects([first]), "single synthetic promise metadata written")
        let before = try temporaryTransfers()
        var outcomes: [Result<Data, Error>] = []
        CalendarDropLoader.loadPromise(board) { outcomes.append($0) }
        let ownedDirectories = try temporaryTransfers().subtracting(before)
        check(ownedDirectories.count == 1, "one private receiving directory allocated")
        for path in ownedDirectories {
            let attributes = try fm.attributesOfItem(atPath: path)
            check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700, "receiving directory is private")
        }
        let limit = Date().addingTimeInterval(11)
        while outcomes.isEmpty && Date() < limit { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        check(outcomes.count == 1, "receive completes or times out within 10 seconds")
        for path in ownedDirectories { check(!fm.fileExists(atPath: path), "receiving directory cleaned after completion") }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        check(outcomes.count == 1, "completion is delivered exactly once")
        if case .success(let result) = outcomes.first! {
            check(result == fixture, "synthetic provider delivery preserves bytes")
        } else {
            print("NOTE synthetic promise had no live drag session; real Calendar drop remains an E2E check")
        }
        print("PASS \(passed) calendar drop-loader checks")
    }

    private static func temporaryTransfers() throws -> Set<String> {
        let directory = FileManager.default.temporaryDirectory
        return Set(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("nowdo-calendar-drop-") }.map(\.path))
    }
}

private final class FixturePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    let data: Data
    init(data: Data) { self.data = data }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        "synthetic-calendar-event.ics"
    }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        do { try data.write(to: url); completionHandler(nil) }
        catch { completionHandler(error) }
    }
}
