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

    /// Pins the reviewer-found limitation so it is visible in the suite, not implied-safe: `Cleared`
    /// guarantees the redaction chokepoint was used, NOT that the content is safe. A weak (identity)
    /// transform passes raw content through — which is why redact call sites must be reviewed.
    func testIdentityTransformIsAKnownUnsafeHazard() {
        let cleared = Redaction.redact(Sensitive(secret)) { $0 }
        XCTAssertEqual(
            cleared.value, secret, "an identity transform does NOT strip content by itself")
    }

    // MARK: log-proofing holds through reflecting + nesting (regression pins)

    func testSensitiveRedactsThroughStringReflecting() {
        XCTAssertEqual(String(reflecting: Sensitive(secret)), "<redacted>")
    }

    func testSensitiveRedactsWhenNestedInContainers() {
        // The highest-value leak vectors: an Optional, an Array, and a wrapping struct.
        let optional: Sensitive<String>? = Sensitive(secret)
        XCTAssertFalse("\(optional as Any)".contains("52.5200"))
        XCTAssertFalse("\([Sensitive(secret)])".contains("52.5200"))

        struct Holder { let field: Sensitive<String> }
        var dumped = ""
        dump(Holder(field: Sensitive(secret)), to: &dumped)
        XCTAssertFalse(dumped.contains("52.5200"), "nested dump must not leak")
        XCTAssertTrue(dumped.contains("<redacted>"))
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
