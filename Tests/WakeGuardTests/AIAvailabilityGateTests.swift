import Foundation
import XCTest

@testable import WakeGuard

/// WG-162: the on-device-model availability gate. Verifies **unsupported/unavailable states produce a
/// deterministic fallback** (AI off, with the reason preserved), that the decision carries **no alarm
/// authority**, that **availability copy is present and honest** for Settings, and — the core invariant —
/// that **no AI feature blocks alarm use**: alarm-scheduling sources never reference AI availability.
final class AIAvailabilityGateTests: XCTestCase {

    private let gate = AIAvailabilityGate()

    // MARK: available ⇒ AI on; unavailable ⇒ deterministic fallback

    func testAvailableEnablesAIFeatures() {
        let decision = gate.decide(for: .available)
        XCTAssertTrue(decision.aiFeaturesEnabled)
        XCTAssertNil(decision.unavailabilityReason)
    }

    func testEveryUnavailableStateDisablesAIWithThatReason() {
        for reason in ModelUnavailabilityReason.allCases {
            let decision = gate.decide(for: .unavailable(reason))
            XCTAssertFalse(decision.aiFeaturesEnabled, "\(reason) must disable AI")
            XCTAssertEqual(decision.unavailabilityReason, reason)
        }
    }

    // MARK: the decision carries no alarm authority

    func testDecisionExposesOnlyAIFieldsNoAlarmAuthority() {
        let fields = Set(
            Mirror(reflecting: gate.decide(for: .available)).children.compactMap(\.label))
        XCTAssertEqual(fields, ["aiFeaturesEnabled", "unavailabilityReason"])
        for forbidden in ["criticality", "command", "alarm", "cancel"] {
            XCTAssertFalse(fields.contains(forbidden))
        }
    }

    // MARK: availability copy is present and honest

    func testPresenterCopyIsDistinctPerStateAndAlwaysReassuresAlarms() {
        let decisions =
            [AIAvailabilityDecision.enabled]
            + ModelUnavailabilityReason.allCases.map(AIAvailabilityDecision.disabled)
        let copies = decisions.map(AIAvailabilityStatusPresenter.copy)

        // Each state gets its own honest detail line.
        XCTAssertEqual(Set(copies.map(\.detail)).count, decisions.count)

        for copy in copies {
            XCTAssertFalse(copy.title.isEmpty)
            XCTAssertFalse(copy.detail.isEmpty)
            // Every state — even "AI off" — reassures that alarms are unaffected (#9).
            XCTAssertTrue(copy.alarmsReassurance.lowercased().contains("alarm"))
        }
    }

    func testPresenterFlagsAvailabilityForTheView() {
        XCTAssertTrue(AIAvailabilityStatusPresenter.copy(for: .enabled).isAvailable)
        XCTAssertFalse(
            AIAvailabilityStatusPresenter.copy(for: .disabled(.modelNotReady)).isAvailable)
    }

    // MARK: no AI feature blocks alarm use (source scan)

    func testAlarmSchedulingSourcesNeverReferenceAIAvailability() throws {
        // Alarm scheduling must not depend on AI availability — otherwise an unavailable model could block
        // alarms. Prove it structurally: the scheduling modules never name any AI-availability symbol.
        let forbidden = [
            "AIAvailabilityGate", "AIAvailabilityDecision", "ModelAvailability",
            "ModelAvailabilityProviding", "aiFeaturesEnabled", "LanguageModelProvider",
        ]
        for module in ["AlarmDomain", "AlarmApplication", "AlarmInfrastructure"] {
            let directory = sourcesDirectory().appendingPathComponent(module)
            let files = swiftFiles(under: directory)
            XCTAssertFalse(files.isEmpty, "expected \(module) sources at \(directory.path)")
            for file in files {
                let source = try code(of: file)
                for token in forbidden {
                    XCTAssertFalse(
                        source.contains(token),
                        "\(file.lastPathComponent) references AI-availability symbol '\(token)' — AI "
                            + "must never gate alarm scheduling")
                }
            }
        }
    }

    // MARK: source-scan helpers

    private func sourcesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    private func code(of file: URL) throws -> String {
        let contents = try String(contentsOf: file, encoding: .utf8)
        var result = ""
        for raw in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") {
                continue
            }
            if let comment = line.range(of: "//") {
                result += line[line.startIndex..<comment.lowerBound] + "\n"
            } else {
                result += line + "\n"
            }
        }
        return result
    }

    private func swiftFiles(under directory: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        return files
    }
}
