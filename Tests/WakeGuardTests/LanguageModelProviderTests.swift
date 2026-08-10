import XCTest

@testable import WakeGuard

/// WG-160: the `LanguageModelProvider` boundary + fake. Verifies the provider returns **typed results or
/// typed failures**, that **no alarm tools are exposed** (the request carries only prompts; the output is
/// inert text), and that the **fake supports malformed and adversarial output**.
final class LanguageModelProviderTests: XCTestCase {

    private let request = LanguageModelRequest(systemPrompt: "s", userPrompt: "u")

    // MARK: typed result or typed failure

    func testProviderReturnsATypedResult() async throws {
        let text = try await ScriptedLanguageModelProvider.returning("hello").generate(request)
        XCTAssertEqual(text, "hello")
    }

    func testProviderThrowsEachTypedFailure() async {
        for expected in LanguageModelError.allCases {
            do {
                _ = try await ScriptedLanguageModelProvider.failing(expected).generate(request)
                XCTFail("expected \(expected) to throw")
            } catch {
                // Typed throws: `error` is a `LanguageModelError`, so failures are compile-time typed.
                XCTAssertEqual(error, expected)
            }
        }
    }

    // MARK: fake supports malformed + adversarial output

    func testFakeSupportsMalformedOutput() async throws {
        let output = try await ScriptedLanguageModelProvider.malformed.generate(request)
        XCTAssertFalse(output.isEmpty)
        XCTAssertNil(
            try? JSONSerialization.jsonObject(with: Data(output.utf8)),
            "malformed output is not valid JSON — the decoder (WG-163) must fail closed")
    }

    func testFakeSupportsAdversarialOutput() async throws {
        // The provider just returns the payload verbatim — it is inert text; the pipeline neutralizes it.
        let output = try await ScriptedLanguageModelProvider.adversarial.generate(request)
        XCTAssertTrue(output.lowercased().contains("cancel every alarm"))
        XCTAssertTrue(output.contains("cancelAlarm"))
    }

    // MARK: no alarm tools are exposed

    func testTheRequestExposesNoToolsOrAlarmCapability() {
        // The request carries only prompt text — no tool list, no command, no alarm reference. Combined
        // with the String-only output, the provider can never act on an alarm (#1/#30).
        let mirror = Mirror(reflecting: request)
        XCTAssertEqual(Set(mirror.children.compactMap(\.label)), ["systemPrompt", "userPrompt"])
    }

    func testProviderOutputIsInertText() async throws {
        // The generate result is a `String` — inert text, never an executable command. (A type-level pin:
        // this wouldn't compile if the provider returned an alarm command.)
        let output: String = try await ScriptedLanguageModelProvider.returning("x").generate(
            request)
        XCTAssertEqual(output, "x")
    }
}
