import SwiftUI
import Combine
import UniformTypeIdentifiers

/// Short-lived alerts that briefly widen the notch ("live activities").
enum TransientActivity: Equatable {
    case charging(Int)
    case onBattery(Int)
    case lowBattery(Int)
    case timerDone
    case shelfAdded(Int)
    case upcomingEvent(title: String, minutes: Int)
}

final class NotchViewModel: ObservableObject {
    enum Status { case closed, open }
    enum DisplayState: Equatable { case closed, peek, open }

    enum Tab: String, CaseIterable, Identifiable {
        case home, shelf, calendar
        var id: Self { self }
        var icon: String {
            switch self {
            case .home: return "music.note.house.fill"
            case .shelf: return "tray.full.fill"
            case .calendar: return "calendar"
            }
        }
        var title: String { rawValue.capitalized }
    }

    // MARK: Layout constants
    static let wing: CGFloat = 74                              // width of each side "ear" in peek mode
    static let openSize = CGSize(width: 640, height: 214)

    // MARK: State
    @Published private(set) var status: Status = .closed
    @Published var tab: Tab = .home
    @Published private(set) var notchSize = CGSize(width: 185, height: 32)
    @Published private(set) var hasPhysicalNotch = true
    @Published private(set) var peekActive = false
    @Published private(set) var transient: TransientActivity?
    @Published var isDropTargeted = false

    // MARK: Feature modules
    let media = MediaController()
    let shelf = ShelfStore()
    let calendar = CalendarStore()
    let battery = BatteryMonitor()
    let timer = TimerActivity()

    private var cancellables = Set<AnyCancellable>()
    private var transientWork: DispatchWorkItem?
    private var calendarTimer: Timer?
    private var notifiedEventIDs = Set<String>()
    private var lastBatteryLevel = 100

    /// User setting (menu bar → "Show Live Activities Beside Notch").
    @Published var liveActivitiesEnabled: Bool = UserDefaults.standard.object(forKey: "NotchIsland.liveActivities") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(liveActivitiesEnabled, forKey: "NotchIsland.liveActivities")
            updatePeek()
        }
    }

    /// Music counts as "live" only when we positively know a track is playing.
    var mediaIsLive: Bool { media.isPlaying && media.track != nil }

    init() {
        // Peek (widened notch) only while something is actually live. Every source
        // re-evaluates from current values, so the ears can never get stuck on.
        Publishers.MergeMany(
            media.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            timer.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            $transient.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: DispatchQueue.main)   // runs after the new values are set
        .sink { [weak self] in self?.updatePeek() }
        .store(in: &cancellables)

        // Safety net: re-check every 2 s in case any change was missed.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.updatePeek() }
        }

        // Charger plugged / unplugged.
        battery.$isPluggedIn
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] plugged in
                guard let self, self.battery.hasBattery else { return }
                self.show(plugged ? .charging(self.battery.level) : .onBattery(self.battery.level))
            }
            .store(in: &cancellables)

        // Low battery warning when crossing 20 %.
        lastBatteryLevel = battery.level
        battery.$level
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self else { return }
                if !self.battery.isPluggedIn, self.lastBatteryLevel > 20, level <= 20 {
                    self.show(.lowBattery(level))
                }
                self.lastBatteryLevel = level
            }
            .store(in: &cancellables)

        // Dragging a file over the island opens the shelf.
        $isDropTargeted
            .removeDuplicates()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.open(tab: .shelf) }
            .store(in: &cancellables)

        timer.onFinish = { [weak self] in self?.show(.timerDone) }

        calendarTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.checkUpcomingEvents() }
        }
    }

    func updatePeek() {
        let live = liveActivitiesEnabled && (transient != nil || timer.isRunning || mediaIsLive)
        if live != peekActive { peekActive = live }
    }

    // MARK: Derived layout

    var displayState: DisplayState {
        if status == .open { return .open }
        return peekActive ? .peek : .closed
    }

    var radii: (top: CGFloat, bottom: CGFloat) {
        switch displayState {
        case .closed: return (6, 10)
        case .peek: return (6, 12)
        case .open: return (14, 26)
        }
    }

    /// Full size of the black shape, including the outward-flaring top corners.
    var visibleSize: CGSize {
        let r = radii.top * 2
        switch displayState {
        case .closed: return CGSize(width: notchSize.width + r, height: notchSize.height)
        case .peek: return CGSize(width: notchSize.width + Self.wing * 2 + r, height: notchSize.height)
        case .open: return Self.openSize
        }
    }

    // MARK: Actions

    func applyGeometry(_ geometry: NotchGeometry) {
        notchSize = geometry.notchSize
        hasPhysicalNotch = geometry.hasNotch
    }

    func open(tab: Tab) {
        self.tab = tab
        if status != .open { status = .open }
    }

    func close() {
        if status != .closed { status = .closed }
    }

    func show(_ activity: TransientActivity, for seconds: Double = 3) {
        transientWork?.cancel()
        transient = activity
        let work = DispatchWorkItem { [weak self] in self?.transient = nil }
        transientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !fileProviders.isEmpty else { return false }

        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()

        for provider in fileProviders {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self, !urls.isEmpty else { return }
            self.shelf.add(urls)
            self.tab = .shelf
            if self.status != .open { self.show(.shelfAdded(urls.count)) }
        }
        return true
    }

    private func checkUpcomingEvents() {
        guard calendar.authorized, let event = calendar.nextEvent(within: 10 * 60),
              let id = event.eventIdentifier, !notifiedEventIDs.contains(id) else { return }
        notifiedEventIDs.insert(id)
        let minutes = max(1, Int((event.startDate.timeIntervalSinceNow / 60).rounded(.up)))
        show(.upcomingEvent(title: event.title ?? "Event", minutes: minutes), for: 6)
    }
}
