import Foundation
import XCTest

@testable import WakeGuard

/// WG-220: coarse privacy-safe analytics. Verifies the **event schema forbids sensitive payloads** (only
/// flags/buckets/closed-enum categories — no free text), that analytics **can be fully disabled** (the gate
/// records nothing when off, and it's off by default), and that **no SDK is required** (the default sink is
/// a no-op; the module imports nothing third-party).
final class AnalyticsTests: XCTestCase {

    private let allEvents: [AnalyticsEvent] = [
        .alarmCreated(isCritical: true),
        .agentChangeApplied(confirmed: false),
        .challengeFinished(passed: true),
        .onboardingCompleted(skippedFirstAlarm: false),
        .optionalFeatureToggled(feature: .health, enabled: true),
        .dataExportPrepared,
        .dataDeleted(scope: .all),
    ]

    // MARK: schema forbids sensitive payloads

    func testEventPropertiesAreOnlyFlagsBucketsOrClosedEnumCategories() {
        let allowedCategories = Set(
            AnalyticsFeature.allCases.map(\.rawValue)
                + AnalyticsDeletionScope.allCases.map(\.rawValue))
        for event in allEvents {
            for (_, value) in event.properties {
                switch value {
                case .flag, .bucket:
                    continue
                case .category(let category):
                    XCTAssertTrue(
                        allowedCategories.contains(category),
                        "category '\(category)' isn't from a closed enum — free text could leak")
                }
            }
            XCTAssertFalse(event.name.isEmpty)
        }
    }

    // MARK: fully disableable

    func testDisabledAnalyticsRecordsNothing() {
        let sink = RecordingAnalyticsSink()
        let gated = GatedAnalytics(underlying: sink, isEnabled: { false })
        for event in allEvents { gated.record(event) }
        XCTAssertTrue(sink.recorded.isEmpty, "disabled analytics must record nothing")
    }

    func testEnabledAnalyticsForwardsEvents() {
        let sink = RecordingAnalyticsSink()
        let gated = GatedAnalytics(underlying: sink, isEnabled: { true })
        gated.record(.alarmCreated(isCritical: false))
        XCTAssertEqual(sink.recorded, [.alarmCreated(isCritical: false)])
    }

    func testAnalyticsIsOffByDefault() {
        XCTAssertFalse(AppSettings.default.analyticsEnabled)
    }

    // MARK: no SDK required

    func testDefaultSinkIsNoOpAndModuleHasNoSDK() throws {
        // The no-op default builds and runs with no third-party dependency.
        NoOpAnalyticsSink().record(.dataExportPrepared)
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Observability/Analytics.swift")
        let code = try String(contentsOf: file, encoding: .utf8)
        for sdk in ["import Firebase", "import Mixpanel", "import Amplitude", "import Segment"] {
            XCTAssertFalse(code.contains(sdk))
        }
    }
}

/// Records events for assertions.
private final class RecordingAnalyticsSink: AnalyticsSink {
    private let box = Synchronized<[AnalyticsEvent]>([])
    var recorded: [AnalyticsEvent] { box.get() }
    func record(_ event: AnalyticsEvent) { box.mutate { $0.append(event) } }
}
