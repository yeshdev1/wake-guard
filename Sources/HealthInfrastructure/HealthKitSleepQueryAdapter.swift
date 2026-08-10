import Foundation
import HealthKit
import Synchronization

/// Runs the sleep-analysis query against `HKHealthStore` (device-only, WG-122). It queries a **bounded**
/// window (`SleepQueryWindow`), maps each `HKCategorySample`'s **raw value** to a domain `SleepCategory`
/// via the pure mapper (skipping unknown/malformed samples, fail-closed), and returns an
/// **overlap-resolved** timeline (`SleepTimeline.normalize`). The query is **cancelable** — task
/// cancellation stops the running `HKSampleQuery` and resumes with `CancellationError`, with a
/// single-resume guard so the continuation neither leaks nor double-resumes. `@unchecked Sendable`:
/// `HKHealthStore` is documented thread-safe and the only stored state.
struct HealthKitSleepQueryAdapter: SleepSampleQuerying, @unchecked Sendable {
    private typealias SampleContinuation = CheckedContinuation<[HKCategorySample], Error>

    private let store = HKHealthStore()

    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
        let window = SleepQueryWindow(end: end, requestedStart: start)
        guard !window.isEmpty,
            let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        else { return [] }
        try Task.checkCancellation()

        let raw = try await execute(sleepType, window: window)
        let mapped = raw.compactMap { sample -> SleepSample? in
            guard let category = SleepCategory(healthKitSleepValue: sample.value) else {
                return nil
            }
            return SleepSample(category: category, start: sample.startDate, end: sample.endDate)
        }
        return SleepTimeline.normalize(mapped)
    }

    private struct QueryState {
        var query: HKSampleQuery?
        var continuation: SampleContinuation?
        var resumed = false
    }

    private func execute(_ type: HKCategoryType, window: SleepQueryWindow) async throws
        -> [HKCategorySample]
    {
        let predicate = HKQuery.predicateForSamples(
            withStart: window.start, end: window.end, options: [.strictStartDate])
        let state = Mutex(QueryState())

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: SampleContinuation) in
                let query = HKSampleQuery(
                    sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, samples, error in
                    let cont = state.withLock { current -> SampleContinuation? in
                        guard !current.resumed else { return nil }
                        current.resumed = true
                        return current.continuation
                    }
                    if let error {
                        cont?.resume(throwing: error)
                    } else {
                        cont?.resume(returning: (samples as? [HKCategorySample]) ?? [])
                    }
                }
                let cancelledEarly = state.withLock { current -> Bool in
                    if current.resumed { return true }
                    current.query = query
                    current.continuation = continuation
                    return false
                }
                if cancelledEarly {
                    continuation.resume(throwing: CancellationError())
                } else {
                    store.execute(query)
                }
            }
        } onCancel: {
            let resume = state.withLock { current -> (HKSampleQuery?, SampleContinuation?) in
                guard !current.resumed else { return (nil, nil) }
                current.resumed = true
                return (current.query, current.continuation)
            }
            // `resumed` is flipped INSIDE the lock above, then `stop`/`resume` run OUTSIDE it. This is
            // load-bearing: `store.stop` can invoke the results handler **synchronously**, which re-enters
            // `state.withLock` — safe only because the lock is already released (no deadlock on the
            // non-recursive Mutex) and it sees `resumed == true`, so it no-ops. Single-resume holds.
            if let query = resume.0 { store.stop(query) }
            resume.1?.resume(throwing: CancellationError())
        }
    }
}
