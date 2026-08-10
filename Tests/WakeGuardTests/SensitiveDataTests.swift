import Foundation
import XCTest

@testable import WakeGuard

/// WG-181: sensitive-data classification types. Verifies a `Sensitive` value **cannot be read through any
/// normal logging API** (description / interpolation / `String(describing:)` / `dump` / `Mirror` all
/// redact), that the raw value is reachable only via the explicit `reveal()`, and that a **cloud-bound
/// builder requires a `Redacted` type** reachable only through the redaction boundary.
final class SensitiveDataTests: XCTestCase {

    private let secret = "TOPSECRET-52.5200-13.4050"

    func testSensitiveRedactsThroughEveryStringAPI() {
        let sensitive = Sensitive(secret)
        XCTAssertEqual(sensitive.description, "<redacted>")
        XCTAssertEqual(sensitive.debugDescription, "<redacted>")
        XCTAssertEqual(String(describing: sensitive), "<redacted>")
        XCTAssertEqual("\(sensitive)", "<redacted>")
        XCTAssertFalse("\(sensitive)".contains("52.5200"), "interpolation must not leak the value")
    }

    func testSensitiveRedactsThroughDumpAndMirror() {
        let sensitive = Sensitive(secret)
        var dumped = ""
        dump(sensitive, to: &dumped)
        XCTAssertTrue(dumped.contains("<redacted>"))
        XCTAssertFalse(dumped.contains("52.5200"), "dump must not walk to the value")

        let mirrored = Mirror(reflecting: sensitive).children.map { "\($0.value)" }.joined()
        XCTAssertFalse(mirrored.contains("52.5200"), "Mirror must not expose the value")
    }

    func testRevealReturnsTheRawValue() {
        XCTAssertEqual(Sensitive(secret).reveal(), secret)
    }

    func testSensitiveIsEquatableWhenValueIs() {
        XCTAssertEqual(Sensitive(secret), Sensitive(secret))
        XCTAssertNotEqual(Sensitive(secret), Sensitive("other"))
    }

    // MARK: redaction boundary + cloud-bound builder

    func testRedactionIsTheOnlyPathToRedacted() {
        // A precise location is redacted to a coarse region — the transform is where sensitivity is
        // stripped; only its output may leave the device.
        let coordinates = Sensitive("52.5200,13.4050")
        let redacted = Redaction.redact(coordinates) { _ in "region:Berlin" }
        XCTAssertEqual(redacted.value, "region:Berlin")
        XCTAssertFalse(redacted.value.contains("52.5200"))
    }

    func testCloudBoundBuilderRequiresAClearedType() {
        // The builder's initializer takes `Cleared<String>` — a raw `String` or `Sensitive` cannot be
        // passed (a compiler boundary), so un-redacted data can't be built into a cloud payload.
        let cleared = Redaction.redact(Sensitive("journal: I slept badly")) { _ in "quality:poor" }
        let payload = CloudBoundText(cleared)
        XCTAssertEqual(payload.value, "quality:poor")
    }
}

/// A cloud-bound payload builder used to prove the compiler boundary: it accepts **only** a
/// `Cleared<String>`.
private struct CloudBoundText {
    let value: String

    init(_ cleared: Cleared<String>) {
        value = cleared.value
    }
}
