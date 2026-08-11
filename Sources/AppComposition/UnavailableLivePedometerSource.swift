import Foundation

/// A hermetic live `PedometerSource` for the in-memory graph (WG-073): it reports the live pedometer as
/// **not present** and yields no samples, so previews/tests compose the challenge runtime without touching
/// CoreMotion (the challenge then offers the accessible alternative, #21/#22). Production uses
/// `CoreMotionLivePedometerAdapter`.
struct UnavailableLivePedometerSource: PedometerSource {
    func availability() async -> MotionSourceAvailability { .notPresent }

    func samples() -> AsyncThrowingStream<PedometerSample, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
