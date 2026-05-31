import Foundation

/// Fires on each local wall-clock minute boundary (:00), then reschedules.
final class MinuteBoundaryTimer {
    private var timer: DispatchSourceTimer?
    private var onTick: (() -> Void)?

    func start(onTick: @escaping () -> Void) {
        self.onTick = onTick
        reschedule()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        onTick = nil
    }

    func reschedule() {
        guard onTick != nil else { return }
        timer?.cancel()
        timer = nil
        scheduleNextFire()
    }

    private func scheduleNextFire() {
        guard let onTick else { return }
        let delay = Self.secondsUntilNextMinute()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + delay, repeating: .never)
        source.setEventHandler { [weak self] in
            onTick()
            self?.timer?.cancel()
            self?.timer = nil
            self?.scheduleNextFire()
        }
        source.resume()
        timer = source
    }

    static func secondsUntilNextMinute(from date: Date = Date()) -> TimeInterval {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.second, .nanosecond], from: date)
        let seconds = Double(components.second ?? 0)
        let nanoseconds = Double(components.nanosecond ?? 0) / 1_000_000_000
        return 60.0 - (seconds + nanoseconds)
    }
}
