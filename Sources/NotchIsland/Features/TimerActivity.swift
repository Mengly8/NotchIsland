import AppKit
import Combine

/// A countdown timer that lives in the notch while it runs.
final class TimerActivity: ObservableObject {
    @Published private(set) var endDate: Date?
    @Published private(set) var total: TimeInterval = 0

    var onFinish: (() -> Void)?
    var isRunning: Bool { endDate != nil }

    private var ticker: Timer?

    func start(minutes: Double) {
        total = minutes * 60
        endDate = Date().addingTimeInterval(total)
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.tick() }
        }
    }

    func cancel() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
    }

    func remaining(at date: Date) -> TimeInterval {
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(date))
    }

    func progress(at date: Date) -> Double {
        guard total > 0 else { return 0 }
        return 1 - remaining(at: date) / total
    }

    private func tick() {
        guard let endDate, endDate <= Date() else { return }
        cancel()
        NSSound(named: "Glass")?.play()
        onFinish?()
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
