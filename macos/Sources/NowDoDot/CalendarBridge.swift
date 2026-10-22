import AppKit
import EventKit
import NowDoCore

@MainActor
final class CalendarBridge: ObservableObject {
    @Published var items: [WorkItem] = []
    @Published var calendars: [(id: String, title: String)] = []
    @Published var status = EKEventStore.authorizationStatus(for: .event)
    @Published var error: String?
    @Published var loading = false
    private let store = EKEventStore()
    private let disabled: Bool
    private var observer: NSObjectProtocol?
    var date = Date()
    var excluded: Set<String> {
        didSet { UserDefaults.standard.set(Array(excluded), forKey: "excludedCalendars"); refresh() }
    }
    var allowed: Bool { !disabled && status == .fullAccess }

    init(disabled: Bool = false) {
        self.disabled = disabled
        excluded = Set(UserDefaults.standard.stringArray(forKey: "excludedCalendars") ?? [])
        if disabled { status = .notDetermined; return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func connect() {
        guard !disabled else { return }
        loading = true
        store.requestFullAccessToEvents { [weak self] granted, failure in
            Task { @MainActor in
                guard let self else { return }
                self.loading = false
                self.status = EKEventStore.authorizationStatus(for: .event)
                if let failure { self.error = failure.localizedDescription }
                else if !granted { self.error = "还没有日历权限。你仍可使用临时事项计时。" }
                self.refresh()
            }
        }
    }

    func refresh() {
        guard !disabled else { return }
        status = EKEventStore.authorizationStatus(for: .event)
        guard allowed else { items = []; calendars = []; return }
        let available = store.calendars(for: .event)
        calendars = available.map { ($0.calendarIdentifier, $0.title) }.sorted { $0.title < $1.title }
        let selected = available.filter { !excluded.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { items = []; return }
        let day = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let predicate = store.predicateForEvents(withStart: day, end: end, calendars: selected)
        var seen = Set<String>()
        items = store.events(matching: predicate).sorted {
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            return $0.startDate < $1.startDate
        }.compactMap { event in
            let item = workItem(event)
            guard seen.insert(item.id).inserted else { return nil }
            return item
        }
        error = nil
    }

    /// Bind only an exact, unique occurrence. Titles alone cannot identify a calendar event.
    func match(_ selection: CalendarSelection) -> WorkItem? {
        guard !disabled, EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              !selection.hasRecurrence || selection.recurrenceID != nil else { return nil }
        let predicate = store.predicateForEvents(withStart: selection.start.addingTimeInterval(-1),
                                                end: selection.start.addingTimeInterval(1), calendars: nil)
        let matches = store.events(matching: predicate).filter { event in
            guard event.calendarItemExternalIdentifier == selection.uid,
                  event.isAllDay == selection.isAllDay,
                  abs(event.startDate.timeIntervalSince(selection.start)) < 1 else { return false }
            if let recurrence = selection.recurrenceID {
                guard let occurrence = event.occurrenceDate, abs(occurrence.timeIntervalSince(recurrence)) < 1 else { return false }
            }
            return true
        }
        guard matches.count == 1 else { return nil }
        return workItem(matches[0])
    }

    private func workItem(_ event: EKEvent) -> WorkItem {
        let occurrence = event.occurrenceDate ?? event.startDate!
        let key = "event|\(event.calendar.calendarIdentifier)|\(event.calendarItemIdentifier)|\(Int(occurrence.timeIntervalSince1970))"
        return WorkItem(id: key, title: event.title?.isEmpty == false ? event.title! : "未命名日程",
                        calendarName: event.calendar.title, plannedStart: event.startDate,
                        plannedDuration: event.isAllDay ? nil : max(0, event.endDate.timeIntervalSince(event.startDate)),
                        isAllDay: event.isAllDay, createdAt: Date())
    }
}
