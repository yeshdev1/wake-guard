import Foundation

/// Watches the device time zone (WG-100): reconciles against the current zone at **launch** (catching a
/// change missed while the app was closed) and subscribes to `NSSystemTimeZoneDidChange` for **live**
/// changes, routing each detected change to `onChange`. The only component that reads `TimeZone.current`
/// / the system notification; the detection logic is the pure `TimeZoneChangeDetector`.
///
/// A **non-IANA** current zone (a fixed-offset simulator zone, #11) is skipped fail-closed — never a
/// crash, and never a spurious change. Advisory only: a detected change is handed to `onChange`; it
/// carries no alarm authority.
///
/// `@unchecked Sendable` (deliberate): the immutable `detector` + `@Sendable onChange` are the only
/// state the notification callback touches; `token` is mutated solely by `start`/`stop`, which the app
/// calls on the main actor.
final class SystemTimeZoneMonitor: @unchecked Sendable {
    private let detector: TimeZoneChangeDetector
    private let onChange: @Sendable (TimeZoneChange) -> Void
    private var token: (any NSObjectProtocol)?

    init(store: any TimeZoneStateStore, onChange: @escaping @Sendable (TimeZoneChange) -> Void) {
        detector = TimeZoneChangeDetector(store: store)
        self.onChange = onChange
    }

    /// Reconcile against the current zone (call at launch — seeds the baseline and catches a missed
    /// change), then subscribe to future system changes. Safe to call once per launch.
    func start() {
        reconcile()
        token = NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reconcile()
        }
    }

    func stop() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }

    private func reconcile() {
        // A live notification means the system zone changed; refresh Foundation's cached value first.
        NSTimeZone.resetSystemTimeZone()
        guard let current = try? IANATimeZone(TimeZone.current) else { return }
        if let change = detector.observe(current: current) { onChange(change) }
    }
}
