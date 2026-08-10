import Foundation

/// A category of local data with its **own** retention window (WG-182). Kept separate so motion history,
/// the audit log, recommendations, and journal entries each expire on their own schedule.
enum RetentionCategory: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case derivedMotion
    case audit
    case recommendations
    case journal
}

/// A local record considered for cleanup (WG-182): its category, when it was created, and — for audit —
/// whether it concerns a **critical** alarm (which has a longer, floored retention).
struct RetentionRecord: Sendable, Equatable, Hashable {
    let category: RetentionCategory
    let createdAt: Date
    /// `true` only for audit events about a critical alarm; ignored for other categories.
    let isCriticalAudit: Bool

    init(category: RetentionCategory, createdAt: Date, isCriticalAudit: Bool = false) {
        self.category = category
        self.createdAt = createdAt
        self.isCriticalAudit = isCriticalAudit
    }
}

/// Per-category local-data retention windows (WG-182). Privacy-first: derived data expires soonest; the
/// audit log is kept longer for accountability, and **critical-alarm audit events have a documented
/// minimum floor** so a safety-relevant change to a critical alarm can never be purged early — even if the
/// general audit window is shortened.
struct RetentionPolicy: Sendable, Equatable, Hashable {
    let derivedMotion: TimeInterval
    let audit: TimeInterval
    let recommendations: TimeInterval
    let journal: TimeInterval

    /// **Documented critical-audit minimum:** audit events about a critical alarm are retained for at least
    /// **365 days**, regardless of the general audit window. This is a floor, not a cap.
    static let criticalAuditMinimum: TimeInterval = 365 * 86_400

    static let `default` = RetentionPolicy(
        derivedMotion: 14 * 86_400, audit: 180 * 86_400, recommendations: 30 * 86_400,
        journal: 365 * 86_400)

    func window(for category: RetentionCategory) -> TimeInterval {
        switch category {
        case .derivedMotion: derivedMotion
        case .audit: audit
        case .recommendations: recommendations
        case .journal: journal
        }
    }

    /// The retention actually applied to a record — the category window, raised to the critical-audit floor
    /// for a critical audit event.
    func effectiveRetention(for record: RetentionRecord) -> TimeInterval {
        let base = window(for: record.category)
        if record.category == .audit, record.isCriticalAudit {
            return max(base, Self.criticalAuditMinimum)
        }
        return base
    }
}

/// The deterministic retention cleanup (WG-182): given records + a policy + `now`, returns the records
/// eligible for deletion. Pure and total, so cleanup is fully testable; a critical audit event is never
/// returned before the documented floor.
enum RetentionCleanup {
    static func expired(
        _ records: [RetentionRecord], policy: RetentionPolicy = .default, now: Date
    ) -> [RetentionRecord] {
        records.filter { record in
            now.timeIntervalSince(record.createdAt) > policy.effectiveRetention(for: record)
        }
    }

    static func retained(
        _ records: [RetentionRecord], policy: RetentionPolicy = .default, now: Date
    ) -> [RetentionRecord] {
        let expired = Set(expired(records, policy: policy, now: now))
        return records.filter { !expired.contains($0) }
    }
}
