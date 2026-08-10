import Foundation

/// A data type WakeGuard touches, for the App Store privacy "nutrition label" (WG-187).
enum NutritionDataType: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case healthAndFitness
    case coarseLocation
    case calendarEvents
    case userContent
    case diagnostics
    /// The only data that may leave the device: minimized, redacted derived summaries sent to the optional
    /// cloud model when the user enables it.
    case cloudDerivedSummaries
}

/// How a data type is handled for the nutrition label (WG-187).
enum NutritionCollection: String, Sendable, Equatable, Hashable, Codable {
    /// Processed on device and **never transmitted**.
    case notCollected
    /// Transmitted **only** when the user enables cloud AI, and only in **redacted** form.
    case optionalRedacted
}

/// One nutrition-label row (WG-187): a data type, whether/how it's collected, and — always false for
/// WakeGuard — whether it is linked to identity or used for tracking.
struct NutritionLabelEntry: Sendable, Equatable, Hashable {
    let dataType: NutritionDataType
    let collection: NutritionCollection
    let linkedToIdentity: Bool
    let usedForTracking: Bool
    let purpose: String
}

/// The App Privacy nutrition-label mapping (WG-187). It accounts for **every** data type the app touches:
/// raw health, location, calendar, and user content are **not collected** (on-device only); the **only**
/// transmitted data is minimized, redacted derived summaries sent to the optional cloud model with separate
/// consent. **Nothing** is linked to identity or used for tracking. The mapping is test-checked against
/// app behavior and the privacy manifest.
enum PrivacyNutritionLabel {
    static let entries: [NutritionLabelEntry] = [
        NutritionLabelEntry(
            dataType: .healthAndFitness, collection: .notCollected, linkedToIdentity: false,
            usedForTracking: false,
            purpose:
                "Sleep is read on device to estimate readiness; raw samples never leave the device."
        ),
        NutritionLabelEntry(
            dataType: .coarseLocation, collection: .notCollected, linkedToIdentity: false,
            usedForTracking: false,
            purpose:
                "Significant-location changes detect time-zone travel on device; never stored or sent."
        ),
        NutritionLabelEntry(
            dataType: .calendarEvents, collection: .notCollected, linkedToIdentity: false,
            usedForTracking: false,
            purpose:
                "Only event times are read on device for wake planning; titles never leave the device."
        ),
        NutritionLabelEntry(
            dataType: .userContent, collection: .notCollected, linkedToIdentity: false,
            usedForTracking: false,
            purpose: "The sleep journal is stored and processed on device."),
        NutritionLabelEntry(
            dataType: .diagnostics, collection: .notCollected, linkedToIdentity: false,
            usedForTracking: false,
            purpose: "No analytics or crash data is transmitted; diagnostics stay on device."),
        NutritionLabelEntry(
            dataType: .cloudDerivedSummaries, collection: .optionalRedacted,
            linkedToIdentity: false,
            usedForTracking: false,
            purpose:
                "When the user turns on cloud AI, only minimized, redacted derived summaries are sent — "
                + "never raw health, location, calendar text, or journal text."),
    ]

    static func entry(for dataType: NutritionDataType) -> NutritionLabelEntry? {
        entries.first { $0.dataType == dataType }
    }

    /// The data types that may ever be transmitted off device.
    static var transmittedDataTypes: [NutritionDataType] {
        entries.filter { $0.collection == .optionalRedacted }.map(\.dataType)
    }
}
