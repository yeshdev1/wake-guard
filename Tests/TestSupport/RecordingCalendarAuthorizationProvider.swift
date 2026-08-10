import Foundation

@testable import WakeGuard

/// A recording `CalendarAuthorizationProviding` for tests: a current status, the status a request would
/// resolve to, and a count of how many times access was requested (to assert access is requested only
/// on opt-in, never automatically).
actor RecordingCalendarAuthorizationProvider: CalendarAuthorizationProviding {
    private let status: CalendarAuthorizationStatus
    private let afterRequest: CalendarAuthorizationStatus
    private(set) var requestCount = 0

    init(
        status: CalendarAuthorizationStatus = .notDetermined,
        afterRequest: CalendarAuthorizationStatus? = nil
    ) {
        self.status = status
        self.afterRequest = afterRequest ?? status
    }

    func authorizationStatus() -> CalendarAuthorizationStatus { status }

    func requestFullAccess() -> CalendarAuthorizationStatus {
        requestCount += 1
        return afterRequest
    }
}
