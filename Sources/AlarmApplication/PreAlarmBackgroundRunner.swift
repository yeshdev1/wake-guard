import Foundation
import Synchronization

/// The app-facing subset of a background task (WG-088), wrapped so the pre-alarm background runner is
/// testable without `BackgroundTasks`. The real adapter conforms a `BGTask`: `setExpirationHandler`
/// assigns `task.expirationHandler`, and `complete(success:)` calls `task.setTaskCompleted(success:)`.
protocol BackgroundTaskHandle: Sendable {
    /// Register the handler the OS invokes when the task is about to be reclaimed.
    func setExpirationHandler(_ handler: @escaping @Sendable () -> Void)
    /// Mark the opportunity finished. The runner calls it exactly once; the real adapter should call
    /// `setTaskCompleted` at most once (a second call must be a no-op — it asserts on some OS versions).
    func complete(success: Bool)
}

/// Runs one pre-alarm background opportunity (WG-088) — **opportunistic and expiration-safe**. Per the
/// architecture rule, a background run is best-effort: it may never happen, and it must never be
/// required to preserve a critical alarm. This runner therefore holds **no alarm authority** — it only
/// runs an injected advisory `work` closure (the pre-alarm evaluation) and reschedules the next
/// opportunity — so a failed, cancelled, or expired run **changes no alarm** (#8-adjacent; a movement
/// inference already can't suppress an alarm, and here even the *opportunity* to infer is best-effort).
///
/// Lifecycle of `run`:
/// 1. **Reschedule the next opportunity first**, at a **bounded** delay (≥ `minimumReschedule`), so a
///    crash / expiry mid-run still leaves one queued and submissions can never tight-loop.
/// 2. Run `work` in a **cancellable** task; register expiration to cancel it — race-free, so an
///    expiration that arrives before the work task is wired still cancels it. `work` **must be
///    cooperatively cancellable** (observe `Task.isCancelled`).
/// 3. **Complete** the task (unsuccessful if the work was cancelled). Reached for a cooperative
///    `work`; an uncooperative one is force-terminated by the OS instead — safe (no alarm seam, and
///    the next opportunity is already queued), just wasteful.
struct PreAlarmBackgroundRunner: Sendable {

    struct Config: Sendable, Equatable {
        /// The floor on the next-opportunity delay — never tighter than this, so background
        /// submissions can't tight-loop. Clamped to a safe minimum; non-finite falls back.
        let minimumReschedule: TimeInterval

        init(minimumReschedule: TimeInterval) {
            self.minimumReschedule =
                (minimumReschedule.isFinite && minimumReschedule >= 60) ? minimumReschedule : 900
        }

        static let `default` = Config(minimumReschedule: 900)
    }

    var config: Config = .default

    /// The next opportunity's earliest request time — bounded (≥ `minimumReschedule`) so submissions
    /// never tight-loop. Pure.
    func nextRequestTime(after now: Date) -> Date {
        now.addingTimeInterval(config.minimumReschedule)
    }

    /// Run one background opportunity. `scheduleNext` submits the next request (the caller wraps
    /// `BGTaskScheduler.submit`); `work` is the advisory pre-alarm evaluation. `now` must come from the
    /// injected `WallClock`, never `Date()`.
    func run(
        _ task: any BackgroundTaskHandle, now: Date,
        scheduleNext: @Sendable (Date) -> Void,
        work: @escaping @Sendable () async -> Void
    ) async {
        // (1) Reschedule first — bounded, and queued even if this run is expired/killed next.
        scheduleNext(nextRequestTime(after: now))
        // (2) Wire expiration → cancellation race-free. The OS can expire almost immediately, before
        // the work task exists, so the handler records the intent under a lock and cancels whatever
        // task is present; storing the task then cancels it if expiration already arrived. Either
        // interleaving cancels the work.
        let control = Mutex<(task: Task<Void, Never>?, expired: Bool)>((nil, false))
        task.setExpirationHandler {
            control.withLock { state in
                state.expired = true
                state.task?.cancel()
            }
        }
        let workTask = Task { await work() }
        control.withLock { state in
            state.task = workTask
            if state.expired { workTask.cancel() }
        }
        await workTask.value
        // (3) Complete — unsuccessful if the work was cancelled (expired), so the OS learns the run
        // didn't finish. Either way no alarm was touched (this runner has no alarm seam).
        task.complete(success: !workTask.isCancelled)
    }
}
