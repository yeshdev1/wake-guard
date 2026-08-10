import Foundation

@testable import WakeGuard

/// A configurable `SignificantLocationSource` for tests: a set authorization status + a canned
/// last-significant-change timestamp (`nil` for denied / none observed).
struct InMemorySignificantLocationSource: SignificantLocationSource {
    var status: LocationAuthorizationStatus = .authorizedWhenInUse
    var lastChange: Date?

    func authorizationStatus() async -> LocationAuthorizationStatus { status }
    func lastSignificantChange() async -> Date? { lastChange }
}
