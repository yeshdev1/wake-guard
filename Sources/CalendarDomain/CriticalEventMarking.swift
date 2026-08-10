import Foundation

/// A mark/unmark of an event's criticality (WG-143).
enum CriticalEventAction: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case marked
    case unmarked
}

/// Who marked an event critical (WG-143). **`user` is the only value** — criticality is confirmed by the
/// user, **never** by a model (#31). The API takes no actor argument, so a model has no path to mark an
/// event critical.
enum CriticalEventActor: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case user
}

/// An append-only audit record of a criticality change (WG-143) — the **evidence** for why an event is
/// treated as a hard wake deadline. Records the event, the action, the actor (always the user), and when.
struct CriticalEventAuditRecord: Sendable, Equatable, Hashable, Codable {
    let eventID: String
    let action: CriticalEventAction
    let actor: CriticalEventActor
    let at: Date
}

/// Persists which events the user marked critical (WG-143). The concrete store is a persistence follow-on.
protocol CriticalEventStore: Sendable {
    func markedEventIDs() async throws -> Set<String>
    func setMarked(_ marked: Bool, eventID: String) async throws
}

/// Append-only audit sink for criticality changes (WG-143).
protocol CriticalEventAuditing: Sendable {
    func record(_ record: CriticalEventAuditRecord) async throws
}

/// Lets the **user** mark a calendar event as critical (a hard wake deadline for WG-145), **reversibly**,
/// with every change **audited** (WG-143). It holds no alarm authority and — crucially — offers no path
/// for a model to set criticality: the actor is always the user (#31).
struct CriticalEventMarking: Sendable {
    let store: any CriticalEventStore
    let audit: any CriticalEventAuditing

    /// Mark an event critical — a **user** action. Audited.
    @discardableResult
    func markCritical(eventID: String, now: Date) async throws -> CriticalEventAuditRecord {
        try await setMarked(true, eventID: eventID, action: .marked, now: now)
    }

    /// **Un-mark** an event — criticality is reversible. Audited.
    @discardableResult
    func unmarkCritical(eventID: String, now: Date) async throws -> CriticalEventAuditRecord {
        try await setMarked(false, eventID: eventID, action: .unmarked, now: now)
    }

    func isCritical(eventID: String) async throws -> Bool {
        try await store.markedEventIDs().contains(eventID)
    }

    private func setMarked(
        _ marked: Bool, eventID: String, action: CriticalEventAction, now: Date
    ) async throws -> CriticalEventAuditRecord {
        try await store.setMarked(marked, eventID: eventID)
        let record = CriticalEventAuditRecord(
            eventID: eventID, action: action, actor: .user, at: now)
        try await audit.record(record)
        return record
    }
}
