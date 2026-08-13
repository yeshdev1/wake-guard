import Foundation

/// The pre-scheduled wake-up re-ring chain (WG-291; ADR WG-293). For a **critical + wake-challenge**
/// alarm, enforcement cannot rely on the app running when the user taps the system Stop (#9: no background
/// task is ever required) — so the re-rings are ordinary AlarmKit alarms scheduled **upfront** alongside the
/// main occurrence, every `interval` up to `maxAttempts` (the confidential 30-minute bound). Stopping one
/// ring without passing simply lets the next pre-scheduled member fire; a pass sweeps the family silent;
/// the bound is physical (a finite chain), surviving reboot and requiring no app logic at ring time.
///
/// Member identity is a **deterministic** function of (parent id, occurrence, index), so scheduling is
/// idempotent (a retry replaces itself), occurrences never collide (per-occurrence ids), and both the
/// scheduler and the reconciler can recompute the family without any stored mapping. Pure Foundation.
enum WakeChain {

    /// The chain entries to schedule behind `occurrence` — empty unless the alarm is critical with a
    /// required challenge (the lock/enforcement combination, WG-293 scope guard).
    static func requests(
        for alarm: Alarm, occurrence: Date, config: RearmConfiguration = .default
    ) -> [AlarmScheduleRequest] {
        guard alarm.criticality == .critical, alarm.challengePolicy.isRequired else { return [] }
        return (1...max(1, config.maxAttempts)).compactMap { index in
            guard index <= config.maxAttempts else { return nil }
            var request = AlarmScheduleRequest(
                alarmID: memberID(parent: alarm.id, occurrence: occurrence, index: index),
                fireTime: occurrence.addingTimeInterval(config.interval * Double(index)),
                title: alarm.label, isCritical: true,
                requiredSteps: alarm.challengePolicy.requiredSteps)
            request.parentAlarmID = alarm.id
            return request
        }
    }

    /// The family's member ids for one occurrence — for cancel/sweep and reconciliation matching.
    static func memberIDs(
        for alarm: Alarm, occurrence: Date, config: RearmConfiguration = .default
    ) -> [AlarmID] {
        requests(for: alarm, occurrence: occurrence, config: config).map(\.alarmID)
    }

    /// The occurrence that **fired within the live ring window** (`(now − totalWindow, now]`), or nil.
    /// While this returns a value the family is mid-enforcement: the reconciler keeps hands off its
    /// members, and the commitment lock holds (WG-288). Pure — derived entirely from the schedule + `now`.
    static func firedOccurrence(
        for alarm: Alarm, now: Date, deviceTimeZone: TimeZone,
        config: RearmConfiguration = .default
    ) -> Date? {
        guard alarm.criticality == .critical, alarm.challengePolicy.isRequired, alarm.isEnabled,
            config.totalWindow > 0
        else { return nil }
        let engine = AlarmSchedulingEngine()
        guard
            let occurrence = engine.nextOccurrence(
                for: alarm, after: now.addingTimeInterval(-config.totalWindow),
                deviceTimeZone: deviceTimeZone), occurrence <= now
        else { return nil }
        return occurrence
    }

    /// Deterministic member identity: an FNV-1a-derived UUID over (parent, occurrence-second, index) —
    /// stable across runs and processes with no random source (determinism rules), unique per occurrence
    /// so consecutive occurrences' chains coexist without replacing each other.
    static func memberID(parent: AlarmID, occurrence: Date, index: Int) -> AlarmID {
        let seedText =
            "\(parent.rawValue.uuidString)|\(Int64(occurrence.timeIntervalSince1970))|\(index)"
        let bytes = Array(seedText.utf8)
        let high = fnv1a(bytes, seed: 0xcbf2_9ce4_8422_2325)
        let low = fnv1a(bytes, seed: high ^ 0x9e37_79b9_7f4a_7c15)
        var raw = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            raw[i] = UInt8(truncatingIfNeeded: high >> (8 * i))
            raw[8 + i] = UInt8(truncatingIfNeeded: low >> (8 * i))
        }
        raw[6] = (raw[6] & 0x0F) | 0x40  // version 4 shape
        raw[8] = (raw[8] & 0x3F) | 0x80  // RFC 4122 variant
        let uuid = UUID(
            uuid: (
                raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
                raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]
            ))
        return AlarmID(uuid)
    }

    private static func fnv1a(_ bytes: [UInt8], seed: UInt64) -> UInt64 {
        var hash = seed
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
