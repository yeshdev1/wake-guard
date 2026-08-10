import Foundation
import XCTest

@testable import WakeGuard

/// WG-163: the on-device structured-generation adapter. Verifies **guided output decodes into domain
/// DTOs**, that malformed / adversarial / out-of-bounds output **fails closed** to `.malformedOutput`
/// (never a partial or unsafe DTO), that **cancellation and refusal are handled**, and — via a source
/// scan — that **raw prompts and output are never logged** (#41).
final class StructuredGeneratorTests: XCTestCase {

    private let request = LanguageModelRequest(systemPrompt: "s", userPrompt: "u")

    private func generator(_ output: String) -> StructuredGenerator {
        StructuredGenerator(provider: ScriptedLanguageModelProvider.returning(output))
    }

    // MARK: structured output decodes into domain DTOs

    func testDecodesAlarmIntent() async throws {
        let json =
            #"{"hour":7,"minute":30,"recurrence":{"weekdays":["monday"],"date":null},"label":"gym"}"#
        let intent = try await generator(json).generate(AIAlarmIntent.self, for: request)
        XCTAssertEqual(intent.hour, 7)
        XCTAssertEqual(intent.minute, 30)
        XCTAssertEqual(intent.recurrence.weekdays, [.monday])
        XCTAssertEqual(intent.label, "gym")
    }

    func testDecodesTomorrowPlanAndJournal() async throws {
        let planJSON =
            #"{"suggestedWakeHour":6,"suggestedWakeMinute":45,"groundedFactorIDs":["sleepDebt"],"rationale":"r"}"#
        let plan = try await generator(planJSON).generate(AITomorrowPlanProposal.self, for: request)
        XCTAssertEqual(plan.suggestedWakeHour, 6)

        // Unknown quality band fails closed to `.unknown` on decode (WG-161).
        let journalJSON =
            #"{"bedtimeMinutesOfDay":1380,"wakeMinutesOfDay":420,"quality":"stellar","note":null}"#
        let journal = try await generator(journalJSON).generate(
            AIJournalExtraction.self, for: request)
        XCTAssertEqual(journal.quality, .unknown)
    }

    // MARK: fail closed on malformed / adversarial / out-of-bounds

    func testMalformedOutputFailsClosed() async {
        await expectMalformed(ScriptedLanguageModelProvider.malformed)
    }

    func testEmptyOutputFailsClosed() async {
        await expectMalformed(ScriptedLanguageModelProvider.returning("   \n  "))
    }

    func testAdversarialOutputFailsClosedNeverADTO() async {
        // The adversarial script is prose + a fake `cancelAlarm` tool-call — not valid JSON. It can never
        // decode into an intent, so it can never reach policy; it collapses to `.malformedOutput`.
        await expectMalformed(ScriptedLanguageModelProvider.adversarial)
    }

    func testOutOfBoundsValueFailsClosedViaValidate() async {
        // Structurally decodable but hour 25 is out of range — `validate()` rejects it (fail closed).
        let json = #"{"hour":25,"minute":0,"recurrence":{"weekdays":[],"date":null},"label":null}"#
        await expectMalformed(ScriptedLanguageModelProvider.returning(json))
    }

    func testInjectedExtraKeysAreIgnoredAndInert() async throws {
        // Valid JSON carrying injected `criticality`/`tool` keys decodes to the declared fields only —
        // the extras are dropped, so nothing hostile survives into the DTO.
        let json =
            #"{"hour":6,"minute":0,"recurrence":{"weekdays":["monday"],"date":null},"label":"x","#
            + #""criticality":"critical","tool":"cancelAlarm"}"#
        let intent = try await generator(json).generate(AIAlarmIntent.self, for: request)
        XCTAssertEqual(intent.hour, 6)
        let fields = Set(Mirror(reflecting: intent).children.compactMap(\.label))
        XCTAssertFalse(fields.contains("criticality"))
    }

    // MARK: cancellation and refusal are handled

    func testProviderRefusalPropagates() async {
        await expect(.refused, from: ScriptedLanguageModelProvider.failing(.refused))
    }

    func testProviderCancellationPropagates() async {
        await expect(.cancelled, from: ScriptedLanguageModelProvider.failing(.cancelled))
    }

    func testProviderUnavailablePropagates() async {
        await expect(.unavailable, from: ScriptedLanguageModelProvider.failing(.unavailable))
    }

    func testHonorsCooperativeTaskCancellation() async {
        // A provider that returns valid JSON only *after* cancellation — so the generator's post-call
        // cancellation check deterministically trips and yields `.cancelled`, not a decoded intent.
        let json = #"{"hour":7,"minute":0,"recurrence":{"weekdays":[],"date":null},"label":null}"#
        let generator = StructuredGenerator(provider: CancelThenReturnProvider(json: json))
        // Bind locals so the sending `Task` closure captures no non-Sendable `self`.
        let request = request
        let task = Task { () -> LanguageModelError? in
            do {
                _ = try await generator.generate(AIAlarmIntent.self, for: request)
                return nil
            } catch {
                return error as? LanguageModelError
            }
        }
        task.cancel()
        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
    }

    // MARK: raw prompts / output are never logged, persisted, or sent off device (#41, #34/#35)

    func testAIModuleSourcesNeverLogOrExfiltratePromptsOrOutput() throws {
        // Recursively scan BOTH AI module trees — not a fixed allow-list — so a *new* file, or a route
        // into the app's existing `PrivacyLog`/`os.Logger` sink, a file write, or a network call trips
        // this pin. Prompts and model output must never reach any logger, disk, or network.
        let sinks = [
            "print(", "NSLog", "os_log", "OSLog", "Logger", "debugPrint", "dump(",
            "String(reflecting:", "signpost", "PrivacyLog", ".log(",
            "FileHandle", "fputs", "fwrite", ".write(to:", "URLSession", "URLRequest",
        ]
        var scanned = 0
        for directory in aiModuleDirectories() {
            for file in swiftFiles(under: directory) {
                scanned += 1
                let source = try strippedCode(of: file)
                for sink in sinks {
                    XCTAssertFalse(
                        source.contains(sink),
                        "\(file.lastPathComponent) references sink '\(sink)' — prompts/output must never "
                            + "be logged, persisted, or sent off device")
                }
            }
        }
        XCTAssertGreaterThan(scanned, 5, "expected to scan the AI module sources")
    }

    // MARK: helpers

    private func expectMalformed(_ provider: ScriptedLanguageModelProvider) async {
        await expect(.malformedOutput, from: provider)
    }

    private func expect(
        _ expected: LanguageModelError, from provider: ScriptedLanguageModelProvider
    ) async {
        do {
            _ = try await StructuredGenerator(provider: provider).generate(
                AIAlarmIntent.self, for: request)
            XCTFail("expected \(expected)")
        } catch {
            XCTAssertEqual(error, expected)
        }
    }

    private func aiModuleDirectories() -> [URL] {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        return ["AIApplication", "AIInfrastructure"].map(sources.appendingPathComponent)
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

    private func strippedCode(of file: URL) throws -> String {
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
}

/// Returns valid JSON only once the surrounding task is cancelled — lets the cancellation test be
/// deterministic (the generator's post-call `Task.isCancelled` check always trips).
private struct CancelThenReturnProvider: LanguageModelProvider {
    let json: String

    func generate(_ request: LanguageModelRequest) async throws(LanguageModelError) -> String {
        while !Task.isCancelled { await Task.yield() }
        return json
    }
}
