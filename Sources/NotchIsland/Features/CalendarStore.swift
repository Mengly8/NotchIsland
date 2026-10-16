import AppKit
import EventKit
import Combine

/// Today's / selected day's events from the system calendars (iCloud, Google, Exchange…).
final class CalendarStore: ObservableObject {
    @Published private(set) var authorized = false
    @Published private(set) var denied = false
    @Published private(set) var events: [EKEvent] = []
    @Published private(set) var selectedDate = Calendar.current.startOfDay(for: Date())

    private let store = EKEventStore()
    private let calendar = Calendar.current
    private var observer: NSObjectProtocol?

    init() {
        refreshAuthorization()
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// A week strip starting yesterday.
    var days: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (-1...5).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    func requestAccess() {
        NSApp.activate(ignoringOtherApps: true)   // the permission sheet needs a foreground app
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authorized = granted
                self.denied = !granted
                if granted { self.reload() }
            }
        }
    }

    func select(_ date: Date) {
        selectedDate = calendar.startOfDay(for: date)
        reload()
    }

    func reload() {
        guard authorized,
              let end = calendar.date(byAdding: .day, value: 1, to: selectedDate) else { return }
        let predicate = store.predicateForEvents(withStart: selectedDate, end: end, calendars: nil)
        events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    /// Next non-all-day event starting within `seconds` from now.
    func nextEvent(within seconds: TimeInterval) -> EKEvent? {
        guard authorized else { return nil }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(seconds), calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate > now }
            .min { $0.startDate < $1.startDate }
    }

    func isSelected(_ day: Date) -> Bool { calendar.isDate(day, inSameDayAs: selectedDate) }
    func isToday(_ day: Date) -> Bool { calendar.isDateInToday(day) }

    private func refreshAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .event)
        authorized = status == .fullAccess
        denied = status == .denied || status == .restricted
        reload()
    }
}
