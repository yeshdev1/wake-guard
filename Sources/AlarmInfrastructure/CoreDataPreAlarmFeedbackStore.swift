import CoreData
import Foundation

/// The persisted pre-alarm feedback store (WG-090): a **single-row coarse counter** on device — how
/// many times the user reported "I wasn't awake" (a false positive) vs "helpful" after a pre-alarm
/// prompt (WG-083). An `actor` (owns a Core Data context), mirroring the settings-singleton and ledger
/// patterns. It stores **only** the two aggregate tallies — no timestamp, alarm id, occurrence, or raw
/// sample — so it reveals nothing about when the user slept or was prompted (#41/#43).
///
/// **Holds no alarm authority (the WG-090 safety property, structural).** It touches only the
/// `PreAlarmFeedbackRecord` entity and speaks only `PreAlarmFeedbackCategory` / `PreAlarmFeedbackCounts`
/// — no `Alarm`, `AlarmCommand`, adapter, processor, or alarm persistence — so recording feedback can
/// never cancel, delay, reschedule, or retune a critical alarm. There is no path from this tally to
/// scheduling or criticality, so feedback **cannot silently retune critical behavior** (#8/#31).
/// `record` is best-effort: a storage fault silently drops the coarse feedback (the alarm is unaffected
/// either way), so a wedged store at most loses advisory feedback — never a safety regression.
actor CoreDataPreAlarmFeedbackStore: PreAlarmFeedbackStore {
    /// The single feedback row's key (there is exactly one aggregate tally, like `SettingsRecord`).
    private static let singletonKey: Int16 = 0

    private let controller: PersistenceController

    init(_ controller: PersistenceController) {
        self.controller = controller
    }

    private func makeContext() -> NSManagedObjectContext {
        let context = controller.container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.error
        return context
    }

    nonisolated private func request() -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PreAlarmFeedbackRecord")
        request.predicate = NSPredicate(format: "singletonKey == %d", Self.singletonKey)
        request.fetchLimit = 1
        return request
    }

    func record(_ category: PreAlarmFeedbackCategory) async {
        let context = makeContext()
        do {
            try await context.perform {
                let existing = try context.fetch(self.request()).first
                let current = existing.map(Self.decode) ?? .empty
                let updated = current.recording(category)
                let row =
                    existing
                    ?? NSEntityDescription.insertNewObject(
                        forEntityName: "PreAlarmFeedbackRecord", into: context)
                row.setValue(Self.singletonKey, forKey: "singletonKey")
                row.setValue(Int64(clamping: updated.notAwakeCount), forKey: "notAwakeCount")
                row.setValue(Int64(clamping: updated.helpfulCount), forKey: "helpfulCount")
                do {
                    try context.save()
                } catch let error as NSError where Self.isConflict(error) {
                    // A concurrent record won the uniqueness race — roll back and drop this increment
                    // (feedback is coarse + advisory, so an occasional lost tally under contention is
                    // acceptable; the alarm is unaffected either way). Mirrors the outbox/ledger.
                    context.rollback()
                }
            }
        } catch {
            // A genuine storage fault — best-effort, so silently drop the coarse feedback rather than
            // surface an error. The alarm is never affected (WG-090 ADR).
        }
    }

    func counts() async -> PreAlarmFeedbackCounts {
        let context = makeContext()
        do {
            return try await context.perform {
                guard let row = try context.fetch(self.request()).first else { return .empty }
                return Self.decode(row)
            }
        } catch {
            // Unreadable store → report the empty tally (never a spurious count). Advisory read only.
            return .empty
        }
    }

    /// Reads the two coarse counts off a row. `PreAlarmFeedbackCounts` re-clamps at zero, so a missing
    /// or negative stored value can never surface as a negative count.
    nonisolated private static func decode(_ row: NSManagedObject) -> PreAlarmFeedbackCounts {
        let notAwake = (row.value(forKey: "notAwakeCount") as? Int64).map(Int.init(clamping:)) ?? 0
        let helpful = (row.value(forKey: "helpfulCount") as? Int64).map(Int.init(clamping:)) ?? 0
        return PreAlarmFeedbackCounts(notAwakeCount: notAwake, helpfulCount: helpful)
    }

    /// A uniqueness-constraint / merge conflict (a concurrent record won) — distinct from a genuine
    /// storage fault. Mirrors `CoreDataOutboxRepository.isConflict`.
    private static func isConflict(_ error: NSError) -> Bool {
        error.domain == NSCocoaErrorDomain
            && (error.code == NSManagedObjectMergeError
                || error.code == NSManagedObjectConstraintMergeError)
    }
}
