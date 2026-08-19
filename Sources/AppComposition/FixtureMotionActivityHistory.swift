import Foundation

/// A hermetic `MotionActivityHistorySource` for the in-memory graph (WG-310): previews, unit tests and the
/// `-uiTesting` screenshot tour never touch CoreMotion. Production uses `CoreMotionActivityHistoryAdapter`.
///
/// **It returns a night rather than failing (WG-318).** The previous double threw
/// `.unavailable(.notPresent)`, which the section correctly renders as "This device can't track movement" —
/// a claim about the reader's *hardware*, published by a double whose only real property is having no data.
/// That claim reached the committed `11-readiness-degraded` reference screenshot, and it also meant the
/// section's **primary** rendering, an actual estimate, was exercised by nothing at any layer: a double that
/// can only fail can only ever document failure. Every unavailable state still has direct coverage, from
/// doubles owned by the tests that assert them (`ReadinessMovementUnavailabilityTests`).
///
/// This is **not** the `[]` that WG-318 rejected. Returning no samples claims a read happened and found
/// nothing, which the section would report as "not enough movement data"; these are samples, honestly
/// reported, and the real estimator runs over them unchanged. Nothing here fabricates an *estimate* — the
/// fake is the sensor, exactly as the in-memory store is the fake for persistence.
struct FixtureMotionActivityHistory: MotionActivityHistorySource {
    /// Offsets back from the end of the requested window, with the kind each one begins. Anchored to the
    /// window's **end** rather than to absolute dates so the night lands inside whatever span the caller
    /// asks for, and clipped to its start so a short span (the candidate span is only ~6h when the screen is
    /// opened at local midnight) still yields a night rather than nothing.
    ///
    /// Shaped to exercise the parts of the estimator that a flat block would not: an evening walk before
    /// settling, one brief in-night disturbance that must **not** split the night (5m, under
    /// `maxDisturbanceGap`), and a sustained morning run that must close it (20m, over it).
    /// Minutes, not fractional hours: the disturbance is five minutes and the morning run is twenty, and
    /// those two figures are the ones the estimator's thresholds are read against.
    private static let script: [(minutesBeforeEnd: Double, kind: MotionActivityKind)] = [
        (480, .walking),  // out for the evening
        (450, .stationary),  // settled — the night starts here
        (120, .walking),  // a brief disturbance…
        (115, .stationary),  // …five minutes, under `maxDisturbanceGap`, so the night survives it
        (35, .walking),  // up for the day…
        (15, .stationary),  // …twenty minutes, so this run closes the night
    ]

    func activitySamples(in window: DateInterval) async throws -> [MotionActivitySample] {
        // Cancellation is honoured so the preview/test graph matches the real adapter's contract: a consumer
        // that treats `CancellationError` differently from a failure must be able to reach that path here.
        try Task.checkCancellation()
        var samples: [MotionActivitySample] = []
        for entry in Self.script {
            let sample = MotionActivitySample(
                timestamp: max(
                    window.end.addingTimeInterval(-entry.minutesBeforeEnd * 60), window.start),
                quality: .high, kind: entry.kind)
            // Two entries clamp onto `window.start` together whenever the span is shorter than the script —
            // the candidate span is ~6h if the screen is opened at local midnight, against an 8h script. The
            // estimator sorts by timestamp and `sorted(by:)` is **not** stable, so leaving both would let the
            // classification of the span after `window.start` depend on sort order: `.walking` there reads as
            // a four-hour moving run and dissolves the night, and only at some times of day. Keeping the
            // later entry is also the honest reading — the night was already under way when the window
            // opened. The script is time-ascending, so comparing against the last appended sample suffices.
            if samples.last?.timestamp == sample.timestamp { samples.removeLast() }
            samples.append(sample)
        }
        return samples
    }
}
