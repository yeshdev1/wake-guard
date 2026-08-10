import Foundation
import XCTest

@testable import WakeGuard

/// WG-184: accountless local deletion/reset. Verifies the user can delete **optional categories or all
/// data**, that **scheduled-alarm consequences are explicitly confirmed** (a full reset deletes nothing
/// until confirmed, and deleting optional data never touches alarms), and that **deletion is complete**.
final class DataDeletionTests: XCTestCase {

    // MARK: policy

    func testPolicyOnlyFullResetAffectsScheduledAlarms() {
        let policy = DeletionPolicy()
        XCTAssertTrue(policy.affectsScheduledAlarms(.allData))
        XCTAssertFalse(policy.affectsScheduledAlarms(.optionalCategories([.journal])))
    }

    // MARK: optional deletion spares alarms, needs no confirmation

    func testOptionalDeletionProceedsWithoutConfirmationAndSparesAlarms() async {
        let eraser = FakeDataEraser()
        let outcome = await DeletionCoordinator(eraser: eraser).delete(
            .optionalCategories([.journal, .derivedMotion]), userConfirmedAlarmConsequences: false)

        XCTAssertEqual(outcome, .deleted)
        XCTAssertEqual(eraser.stores.erasedOptional, [.journal, .derivedMotion])
        XCTAssertTrue(eraser.stores.alarms, "optional deletion must never touch alarms")
        XCTAssertFalse(eraser.stores.eraseAllCalled)
    }

    // MARK: full reset requires explicit confirmation, deletes nothing otherwise

    func testFullResetWithoutConfirmationDeletesNothing() async {
        let eraser = FakeDataEraser()
        let outcome = await DeletionCoordinator(eraser: eraser).delete(
            .allData, userConfirmedAlarmConsequences: false)

        XCTAssertEqual(outcome, .needsAlarmConsequenceConfirmation)
        XCTAssertTrue(eraser.stores.alarms, "nothing may be deleted without confirmation")
        XCTAssertFalse(eraser.stores.eraseAllCalled)
    }

    func testFullResetWithConfirmationErasesEverythingCompletely() async {
        let eraser = FakeDataEraser()
        let outcome = await DeletionCoordinator(eraser: eraser).delete(
            .allData, userConfirmedAlarmConsequences: true)

        XCTAssertEqual(outcome, .deleted)
        XCTAssertTrue(eraser.stores.eraseAllCalled)
        XCTAssertTrue(eraser.isCompletelyEmpty, "a full reset must delete everything")
    }

    func testDeletionFailurePropagates() async {
        let eraser = FakeDataEraser(shouldThrow: true)
        let outcome = await DeletionCoordinator(eraser: eraser).delete(
            .optionalCategories([.journal]), userConfirmedAlarmConsequences: false)
        XCTAssertEqual(outcome, .failed)
    }

    // MARK: view-model confirmation flow

    @MainActor
    func testFullResetFlowRequiresExplicitConfirmation() async {
        let eraser = FakeDataEraser()
        let model = DataDeletionModel(coordinator: DeletionCoordinator(eraser: eraser))

        model.requestFullReset()
        XCTAssertTrue(model.pendingFullResetConfirmation)
        XCTAssertFalse(eraser.stores.eraseAllCalled, "arming the dialog deletes nothing")
        XCTAssertTrue(eraser.stores.alarms)

        await model.confirmFullReset()
        XCTAssertFalse(model.pendingFullResetConfirmation)
        XCTAssertEqual(model.lastOutcome, .deleted)
        XCTAssertTrue(eraser.stores.eraseAllCalled)
    }

    @MainActor
    func testOptionalDeletionClearsSelection() async {
        let eraser = FakeDataEraser()
        let model = DataDeletionModel(coordinator: DeletionCoordinator(eraser: eraser))
        model.selectedOptional = [.journal]
        await model.deleteSelectedOptional()
        XCTAssertEqual(model.lastOutcome, .deleted)
        XCTAssertTrue(model.selectedOptional.isEmpty)
    }
}

/// An in-memory `DataEraser` that tracks each store so tests can assert alarms are spared by optional
/// deletion and that a full reset is complete.
private final class FakeDataEraser: DataEraser {
    struct Stores: Sendable, Equatable {
        var alarms = true
        var motion = true
        var recommendations = true
        var journal = true
        var health = true
        var settings = true
        var erasedOptional: Set<OptionalDataCategory> = []
        var eraseAllCalled = false
    }

    private let box: Synchronized<Stores>
    private let shouldThrow: Bool

    init(shouldThrow: Bool = false) {
        box = Synchronized(Stores())
        self.shouldThrow = shouldThrow
    }

    var stores: Stores { box.get() }

    var isCompletelyEmpty: Bool {
        let store = box.get()
        return
            !(store.alarms || store.motion || store.recommendations || store.journal
            || store.health || store.settings)
    }

    func eraseOptional(_ categories: Set<OptionalDataCategory>) async throws {
        if shouldThrow { throw CocoaError(.fileWriteUnknown) }
        box.mutate { store in
            store.erasedOptional.formUnion(categories)
            if categories.contains(.derivedMotion) { store.motion = false }
            if categories.contains(.recommendations) { store.recommendations = false }
            if categories.contains(.journal) { store.journal = false }
            if categories.contains(.healthDerived) { store.health = false }
        }
    }

    func eraseAllData() async throws {
        if shouldThrow { throw CocoaError(.fileWriteUnknown) }
        box.mutate { store in
            store.alarms = false
            store.motion = false
            store.recommendations = false
            store.journal = false
            store.health = false
            store.settings = false
            store.eraseAllCalled = true
        }
    }
}
