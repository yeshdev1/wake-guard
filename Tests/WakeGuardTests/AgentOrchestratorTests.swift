import Foundation
import XCTest

@testable import WakeGuard

/// WG-172: the AgentOrchestrator + policy handoff. Verifies the orchestrator **cannot reach AlarmKit or
/// repositories directly** (source-scan; it depends only on the command boundary), that **every submission
/// passes through the policy boundary attributed to the AI** — so the **audit distinguishes an AI proposal
/// from a user action** — and that the permission mode is honoured so a **critical alarm is never mutated
/// without confirmation**.
final class AgentOrchestratorTests: XCTestCase {

    private func command() throws -> AlarmCommand {
        .snooze(AlarmID(try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))))
    }

    // MARK: recommend-only never applies

    func testRecommendOnlyDoesNotSubmit() async throws {
        let processor = RecordingProcessor()
        let orchestrator = AgentOrchestrator(processor: processor)
        let result = await orchestrator.apply(
            try command(), mode: .recommendOnly, targetIsCritical: false, userConfirmed: true)
        XCTAssertEqual(result, .recommendedOnly)
        XCTAssertTrue(processor.calls.isEmpty, "recommend-only must never submit a command")
    }

    // MARK: acting mode requires confirmation

    func testAskBeforeActingWithoutConfirmationDoesNotSubmit() async throws {
        let processor = RecordingProcessor()
        let orchestrator = AgentOrchestrator(processor: processor)
        let result = await orchestrator.apply(
            try command(), mode: .askBeforeActing, targetIsCritical: false, userConfirmed: false)
        XCTAssertEqual(result, .needsUserConfirmation)
        XCTAssertTrue(processor.calls.isEmpty)
    }

    func testAskBeforeActingConfirmedSubmitsAsAnAIProposal() async throws {
        let processor = RecordingProcessor(outcome: .applied)
        let orchestrator = AgentOrchestrator(processor: processor)
        let result = await orchestrator.apply(
            try command(), mode: .askBeforeActing, targetIsCritical: false, userConfirmed: true)
        XCTAssertEqual(result, .handed(.applied))
        XCTAssertEqual(
            processor.calls,
            [.init(source: .agentProposal, actor: .approvedAgentProposal, userConfirmed: true)])
    }

    // MARK: critical alarms are never mutated without confirmation (#6)

    func testCriticalWithoutConfirmationIsNeverSubmitted() async throws {
        let processor = RecordingProcessor()
        let orchestrator = AgentOrchestrator(processor: processor)
        let result = await orchestrator.apply(
            try command(), mode: .askBeforeActing, targetIsCritical: true, userConfirmed: false)
        XCTAssertEqual(result, .needsUserConfirmation)
        XCTAssertTrue(processor.calls.isEmpty, "a critical change must never submit unconfirmed")
    }

    func testCriticalConfirmedSubmitsAsAConfirmedAIProposal() async throws {
        let processor = RecordingProcessor(outcome: .applied)
        let orchestrator = AgentOrchestrator(processor: processor)
        _ = await orchestrator.apply(
            try command(), mode: .askBeforeActing, targetIsCritical: true, userConfirmed: true)
        let call = try XCTUnwrap(processor.calls.first)
        XCTAssertEqual(call.actor, .approvedAgentProposal)
        XCTAssertEqual(call.source, .agentProposal)
        XCTAssertTrue(call.userConfirmed)
    }

    // MARK: the orchestrator never acts as the user

    func testEverySubmissionIsAttributedToTheAINeverTheUser() async throws {
        let processor = RecordingProcessor()
        let orchestrator = AgentOrchestrator(processor: processor)
        _ = await orchestrator.apply(
            try command(), mode: .askBeforeActing, targetIsCritical: false, userConfirmed: true)
        for call in processor.calls {
            XCTAssertNotEqual(
                call.actor, .user, "an AI change must never be logged as a user action")
            XCTAssertEqual(call.actor, .approvedAgentProposal)
        }
    }

    // MARK: cannot reach AlarmKit / repositories directly (source scan)

    func testOrchestratorSourceReachesOnlyTheCommandBoundary() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AlarmApplication/AgentOrchestrator.swift")
        let contents = try String(contentsOf: file, encoding: .utf8)
        var code = ""
        for raw in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") {
                continue
            }
            if let comment = line.range(of: "//") {
                code += line[line.startIndex..<comment.lowerBound] + "\n"
            } else {
                code += line + "\n"
            }
        }
        for forbidden in [
            "import AlarmKit", "AlarmManager", "Repository", "AlarmPolicyEngine",
            "SystemAlarmManager", "persistentContainer", "NSManagedObject",
        ] {
            XCTAssertFalse(
                code.contains(forbidden),
                "orchestrator references '\(forbidden)' — it must reach alarms only via the command "
                    + "boundary")
        }
    }
}

/// Records the attribution of every submitted command, so tests can assert the AI actor/source.
private final class RecordingProcessor: AlarmCommandProcessing {
    struct Call: Sendable, Equatable {
        let source: CommandSource
        let actor: AuditActor
        let userConfirmed: Bool
    }
    private let box = Synchronized<[Call]>([])
    private let outcome: CommandOutcome

    init(outcome: CommandOutcome = .applied) { self.outcome = outcome }

    var calls: [Call] { box.get() }

    func process(
        _ command: AlarmCommand, from source: CommandSource, by actor: AuditActor,
        userConfirmed: Bool
    ) async -> CommandOutcome {
        box.mutate { $0.append(Call(source: source, actor: actor, userConfirmed: userConfirmed)) }
        return outcome
    }

    func reconcile() async -> ReconciliationSummary { ReconciliationSummary() }
}
