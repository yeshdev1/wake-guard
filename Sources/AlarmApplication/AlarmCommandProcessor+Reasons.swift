import Foundation

/// Pure, dependency-free formatters for `AlarmCommandProcessor`: the audit state
/// fingerprint and the user-safe failure-reason strings. Extracted so the actor's core
/// command path stays within the file / type-body budget. These touch neither the adapter
/// nor persistence (no #2 boundary surface) — they only map values to display strings, and
/// stay `static` so they carry no actor isolation.
extension AlarmCommandProcessor {
    /// A stable, non-reversible state fingerprint (FNV-1a over the encoded alarm) — a
    /// hash, never the raw state, so the audit records that state changed without
    /// storing it (#41; #46 old/new state). Used only for intra-trail change detection
    /// (old vs new of the same era), not as a cross-version-stable digest.
    static func hash(_ alarm: Alarm) -> String {
        guard let data = try? JSONEncoder().encode(alarm) else { return "unencodable" }
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            value = (value ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", value)
    }

    static func reason(for error: Error) -> String {
        if let error = error as? AlarmManagerError, case .notAuthorized = error {
            return "Not authorized to schedule alarms."
        }
        return "The alarm could not be updated in the system."
    }

    /// Distinguish a concurrent-edit conflict (the caller should reload and retry) from
    /// a genuine storage failure.
    static func saveFailureReason(for error: Error) -> String {
        if let error = error as? AlarmRepositoryError {
            switch error {
            case .staleRevision, .conflict:
                return "This alarm was changed elsewhere; reload and retry."
            case .storageUnavailable:
                return "The alarm could not be saved."
            }
        }
        return "The alarm could not be saved."
    }
}
