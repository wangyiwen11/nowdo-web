import Foundation

public struct WorkItem: Codable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var calendarName: String
    public var plannedStart: Date?
    public var plannedDuration: TimeInterval?
    public var isAllDay: Bool
    public var createdAt: Date

    public init(id: String, title: String, calendarName: String = "手动事项", plannedStart: Date? = nil,
                plannedDuration: TimeInterval? = nil, isAllDay: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.calendarName = calendarName
        self.plannedStart = plannedStart
        self.plannedDuration = isAllDay ? nil : plannedDuration
        self.isAllDay = isAllDay
        self.createdAt = createdAt
    }
}

public struct TimeSession: Codable, Identifiable, Equatable {
    public var id: UUID
    public var itemID: String
    public var start: Date
    public var end: Date?
    public var note: String
    public var stopReason: String?

    public init(id: UUID = UUID(), itemID: String, start: Date, end: Date? = nil,
                note: String = "", stopReason: String? = nil) {
        self.id = id
        self.itemID = itemID
        self.start = start
        self.end = end
        self.note = note
        self.stopReason = stopReason
    }
}

public struct LedgerState: Codable, Equatable {
    public var items: [WorkItem]
    public var sessions: [TimeSession]
    public var lastCheckpoint: Date?

    public init(items: [WorkItem] = [], sessions: [TimeSession] = [], lastCheckpoint: Date? = nil) {
        self.items = items
        self.sessions = sessions
        self.lastCheckpoint = lastCheckpoint
    }
}

public enum TimerLedgerError: LocalizedError {
    case invalidTime
    case timeMovedBackwards
    case invalidItem
    case unknownSession
    case activeSessionCannotBeTrimmed
    case invalidTrim
    case invalidLedger(String)
    case readFailed(String)
    case writeFailed(String)
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidTime: return "时间无效，未更改记录。"
        case .timeMovedBackwards: return "系统时间早于上一次记录。请检查系统时间后重试，原有记录已保留。"
        case .invalidItem: return "事项信息或计划时长无效，未开始计时。"
        case .unknownSession: return "找不到这段计时记录。"
        case .activeSessionCannotBeTrimmed: return "请先暂停，再修正结束时间。"
        case .invalidTrim: return "修正后的结束时间必须在本段开始与原结束时间之间。"
        case .invalidLedger(let detail): return "计时记录格式有问题，已保留原文件：\(detail)"
        case .readFailed(let detail): return "无法读取计时记录，已保留原文件：\(detail)"
        case .writeFailed(let detail): return "计时记录未能保存，本次操作未生效：\(detail)"
        case .unsupportedVersion(let version): return "此记录由更新版本创建（版本 \(version)），请升级应用后再打开。"
        }
    }
}

/// A single active stopwatch with a durable history. Confine an instance to one thread.
/// Transitions are committed to disk before they become visible in `state`.
public final class TimerLedger {
    public private(set) var state: LedgerState
    public private(set) var recoveredSession: Bool = false
    public let fileURL: URL?

    private struct Document: Codable {
        var version: Int
        var state: LedgerState
    }

    public var activeItemID: String? {
        state.sessions.last(where: { $0.end == nil })?.itemID
    }

    public init(fileURL: URL? = nil, now: Date = Date()) throws {
        guard Self.isFinite(now) else { throw TimerLedgerError.invalidTime }
        self.fileURL = fileURL
        self.state = LedgerState()

        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
            } catch {
                throw TimerLedgerError.readFailed(error.localizedDescription)
            }
            let document: Document
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .millisecondsSince1970
                document = try decoder.decode(Document.self, from: data)
            } catch {
                throw TimerLedgerError.invalidLedger(error.localizedDescription)
            }
            guard document.version == 1 else { throw TimerLedgerError.unsupportedVersion(document.version) }
            try Self.validate(document.state)
            self.state = document.state
        }

        if let index = state.sessions.firstIndex(where: { $0.end == nil }) {
            var recovered = state
            let start = recovered.sessions[index].start
            // Never count time while the app was closed. A backwards clock produces
            // a zero-length segment rather than a negative duration.
            let cutoff = max(start, min(recovered.lastCheckpoint ?? start, now))
            recovered.sessions[index].end = cutoff
            recovered.sessions[index].stopReason = "recovered"
            recovered.lastCheckpoint = cutoff
            try persist(recovered)
            state = recovered
            recoveredSession = true
        }
    }

    public func start(item: WorkItem, at date: Date = Date()) throws {
        guard Self.isFinite(date) else { throw TimerLedgerError.invalidTime }
        guard Self.isValid(item) else { throw TimerLedgerError.invalidItem }
        try requireChronological(date)
        var next = state
        var snapshot = item
        if let index = next.items.firstIndex(where: { $0.id == item.id }) {
            let original = next.items[index]
            snapshot.createdAt = min(original.createdAt, item.createdAt)
            // Compare against the plan as it was when work first started. Editing
            // Calendar later must not silently move the goalposts in the review.
            snapshot.plannedStart = original.plannedStart
            snapshot.plannedDuration = original.plannedDuration
            snapshot.isAllDay = original.isAllDay
            next.items[index] = snapshot
        } else {
            next.items.append(snapshot)
        }

        if let index = next.sessions.firstIndex(where: { $0.end == nil }) {
            if next.sessions[index].itemID == item.id {
                next.lastCheckpoint = date
                try commit(next)
                return
            }
            next.sessions[index].end = date
            next.sessions[index].stopReason = "switched"
        }
        next.sessions.append(TimeSession(itemID: item.id, start: date))
        next.lastCheckpoint = date
        try commit(next)
    }

    public func pause(at date: Date = Date(), reason: String = "manual") throws {
        guard Self.isFinite(date) else { throw TimerLedgerError.invalidTime }
        guard let index = state.sessions.firstIndex(where: { $0.end == nil }) else { return }
        try requireChronological(date)
        var next = state
        next.sessions[index].end = date
        next.sessions[index].stopReason = reason
        next.lastCheckpoint = date
        try commit(next)
    }

    public func checkpoint(at date: Date = Date()) throws {
        guard Self.isFinite(date) else { throw TimerLedgerError.invalidTime }
        guard activeItemID != nil else { return }
        try requireChronological(date)
        var next = state
        next.lastCheckpoint = date
        try commit(next)
    }

    public func setNote(sessionID: UUID, note: String) throws {
        guard let index = state.sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw TimerLedgerError.unknownSession
        }
        var next = state
        next.sessions[index].note = note
        try commit(next)
    }

    /// Shortens a completed segment. It cannot extend into another activity.
    public func trimSession(sessionID: UUID, end: Date) throws {
        guard Self.isFinite(end) else { throw TimerLedgerError.invalidTime }
        guard let index = state.sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw TimerLedgerError.unknownSession
        }
        let session = state.sessions[index]
        guard let previousEnd = session.end else { throw TimerLedgerError.activeSessionCannotBeTrimmed }
        guard end >= session.start, end <= previousEnd else { throw TimerLedgerError.invalidTrim }
        var next = state
        next.sessions[index].end = end
        try commit(next)
    }

    public func seconds(for itemID: String, in interval: DateInterval? = nil, at date: Date = Date()) -> TimeInterval {
        guard Self.isFinite(date) else { return 0 }
        return state.sessions.filter { $0.itemID == itemID }.reduce(0) { total, session in
            let bounds = Self.overlap(session, interval: interval, now: date)
            return total + max(0, bounds.end.timeIntervalSince(bounds.start))
        }
    }

    /// A restorable copy of the exact document format used for local persistence.
    public func backupData() throws -> Data {
        try Self.encode(state)
    }

    /// Exports one row per intersecting segment. A date filter clips segment bounds.
    /// Text cells are neutralized against spreadsheet formula interpretation.
    public func exportCSV(in interval: DateInterval? = nil, at date: Date = Date()) -> String {
        let header = ["事项", "日历", "开始", "结束", "实际分钟", "事项计划分钟", "状态", "停止原因", "备注"]
        var rows = [header.map(Self.csvCell).joined(separator: ",")]
        guard Self.isFinite(date) else { return rows.joined(separator: "\r\n") + "\r\n" }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let items = Dictionary(uniqueKeysWithValues: state.items.map { ($0.id, $0) })

        for session in state.sessions {
            guard let item = items[session.itemID] else { continue }
            let bounds = Self.overlap(session, interval: interval, now: date)
            guard bounds.end > bounds.start else { continue }
            let row = [
                item.title, item.calendarName,
                formatter.string(from: bounds.start), formatter.string(from: bounds.end),
                Self.minutes(bounds.end.timeIntervalSince(bounds.start)),
                item.isAllDay ? "" : item.plannedDuration.map(Self.minutes) ?? "",
                session.end == nil ? "计时中" : "已暂停",
                session.stopReason ?? "", session.note
            ]
            rows.append(row.map(Self.csvCell).joined(separator: ","))
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    private func requireChronological(_ date: Date) throws {
        if let checkpoint = state.lastCheckpoint, date < checkpoint {
            throw TimerLedgerError.timeMovedBackwards
        }
        if let latest = state.sessions.map({ $0.end ?? $0.start }).max(), date < latest {
            throw TimerLedgerError.timeMovedBackwards
        }
    }

    private func commit(_ next: LedgerState) throws {
        try Self.validate(next)
        try persist(next)
        state = next
    }

    private func persist(_ next: LedgerState) throws {
        guard let fileURL else { return }
        do {
            let data = try Self.encode(next)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw TimerLedgerError.writeFailed(error.localizedDescription)
        }
    }

    private static func encode(_ state: LedgerState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Document(version: 1, state: state))
    }

    private static func validate(_ state: LedgerState) throws {
        guard Set(state.items.map(\.id)).count == state.items.count,
              state.items.allSatisfy(isValid) else { throw TimerLedgerError.invalidLedger("事项标识或计划时长无效") }
        guard state.lastCheckpoint.map(isFinite) ?? true else { throw TimerLedgerError.invalidLedger("保存时间无效") }
        let itemIDs = Set(state.items.map(\.id))
        guard Set(state.sessions.map(\.id)).count == state.sessions.count else {
            throw TimerLedgerError.invalidLedger("计时段标识重复")
        }
        var previousEnd: Date?
        var foundActive = false
        for session in state.sessions.sorted(by: { $0.start < $1.start }) {
            guard itemIDs.contains(session.itemID), isFinite(session.start),
                  session.end.map(isFinite) ?? true,
                  session.end.map({ $0 >= session.start }) ?? true else {
                throw TimerLedgerError.invalidLedger("计时段无效或缺少关联事项")
            }
            guard !foundActive, previousEnd.map({ $0 <= session.start }) ?? true else {
                throw TimerLedgerError.invalidLedger("计时段重叠")
            }
            if let end = session.end {
                previousEnd = end
            } else {
                foundActive = true
                guard let checkpoint = state.lastCheckpoint, checkpoint >= session.start else {
                    throw TimerLedgerError.invalidLedger("正在计时的事项缺少有效保存时间")
                }
            }
        }
    }

    private static func isValid(_ item: WorkItem) -> Bool {
        !item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isFinite(item.createdAt) && (item.plannedStart.map(isFinite) ?? true) &&
        (item.plannedDuration.map { $0.isFinite && $0 >= 0 } ?? true) &&
        (!item.isAllDay || item.plannedDuration == nil)
    }

    private static func isFinite(_ date: Date) -> Bool { date.timeIntervalSince1970.isFinite }

    private static func overlap(_ session: TimeSession, interval: DateInterval?, now: Date) -> (start: Date, end: Date) {
        let start = max(session.start, interval?.start ?? session.start)
        let sessionEnd = session.end ?? now
        let end = min(sessionEnd, interval?.end ?? sessionEnd)
        return (start, end)
    }

    private static func minutes(_ seconds: TimeInterval) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), seconds / 60)
    }

    private static func csvCell(_ raw: String) -> String {
        let ignoredPrefix = CharacterSet.whitespacesAndNewlines.union(.controlCharacters).union(CharacterSet(charactersIn: "\u{FEFF}"))
        let first = raw.trimmingCharacters(in: ignoredPrefix).first
        let neutralized = first.map { "=+-@".contains($0) } == true ? "'" + raw : raw
        return "\"" + neutralized.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
