import Foundation
import XCTest

@testable import WakeGuard

/// WG-174: the optional cloud-provider interface. Verifies cloud is **disabled by default**, that it
/// **requires both the feature flag and a separate explicit consent**, and that **sensitive default-deny
/// redaction** is enforced — only `.nonSensitive`-classified text becomes a `CloudSafeText`, and the
/// transport can accept nothing else.
final class CloudProviderTests: XCTestCase {

    private let gate = CloudProviderGate()

    private func settings(enabled: Bool, consented: Bool) -> AppSettings {
        var settings = AppSettings.default
        settings.cloudAIEnabled = enabled
        settings.cloudAIConsented = consented
        return settings
    }

    private func safeRequest() throws -> CloudSafeRequest {
        CloudSafeRequest(
            systemPrompt: try XCTUnwrap(CloudRedactor.clear("s", classification: .nonSensitive)),
            userPrompt: try XCTUnwrap(CloudRedactor.clear("u", classification: .nonSensitive)))
    }

    // MARK: disabled by default

    func testCloudIsDisabledByDefault() {
        XCTAssertFalse(AppSettings.default.cloudAIEnabled)
        XCTAssertFalse(AppSettings.default.cloudAIConsented)
        XCTAssertFalse(gate.isCloudAvailable(settings: .default))
    }

    // MARK: requires both the flag and a separate consent

    func testCloudRequiresFeatureFlagAndSeparateConsent() {
        XCTAssertFalse(gate.isCloudAvailable(settings: settings(enabled: true, consented: false)))
        XCTAssertFalse(gate.isCloudAvailable(settings: settings(enabled: false, consented: true)))
        XCTAssertTrue(gate.isCloudAvailable(settings: settings(enabled: true, consented: true)))
    }

    // MARK: sensitive default-deny redaction

    func testRedactorDeniesSensitiveAndClearsNonSensitive() {
        XCTAssertNil(CloudRedactor.clear("secret", classification: .sensitive))
        let cleared = CloudRedactor.clear("weather is nice", classification: .nonSensitive)
        XCTAssertEqual(cleared?.value, "weather is nice")
    }

    // MARK: the client sends nothing unless available

    func testClientFailsClosedAndSendsNothingWhenGateOff() async throws {
        let transport = SpyCloudTransport()
        let client = CloudLanguageModelClient(
            transport: transport, settings: { AppSettings.default })
        let request = try safeRequest()
        do {
            _ = try await client.generate(request)
            XCTFail("expected .unavailable when cloud is disabled")
        } catch {
            XCTAssertEqual(error, .unavailable)
        }
        XCTAssertTrue(transport.sent.get().isEmpty, "nothing may be sent when cloud is off")
    }

    func testClientSendsWhenEnabledAndConsented() async throws {
        let transport = SpyCloudTransport(output: "cloud-said-hi")
        let allowed = settings(enabled: true, consented: true)
        let client = CloudLanguageModelClient(transport: transport, settings: { allowed })
        let output = try await client.generate(try safeRequest())
        XCTAssertEqual(output, "cloud-said-hi")
        XCTAssertEqual(transport.sent.get().count, 1)
    }

    // MARK: persistence back-compat

    func testConsentDecodesFalseFromALegacyBlob() throws {
        let legacy = #"""
            {"preAlarmPromptEnabled":false,"automaticProposalPreparationEnabled":false,
             "cloudAIEnabled":false,"locationContextEnabled":false,"readinessScoreEnabled":false,
             "experimentalAntiCheatEnabled":false,"analyticsEnabled":false,
             "smartFeaturesKillSwitch":false}
            """#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        XCTAssertFalse(decoded.cloudAIConsented)
    }
}

/// Records cloud requests so tests can assert nothing is sent when cloud is off.
private final class SpyCloudTransport: CloudModelTransport {
    let sent = Synchronized<[CloudSafeRequest]>([])
    private let output: String

    init(output: String = "cloud-result") { self.output = output }

    func send(_ request: CloudSafeRequest) async throws(LanguageModelError) -> String {
        sent.mutate { $0.append(request) }
        return output
    }
}
