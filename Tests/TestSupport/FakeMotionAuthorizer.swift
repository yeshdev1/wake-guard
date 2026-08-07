import Foundation

@testable import WakeGuard

/// A configurable `MotionAuthorizing` for tests (WG-061): reports a current status, returns a set
/// status after a request (or throws to model an interrupted request), and counts requests so a
/// test can assert the request happens **only** on `requestAfterExplanation`, never on reading the
/// current step. An `actor`, so it is `Sendable` with no locking boilerplate.
actor FakeMotionAuthorizer: MotionAuthorizing {
    private var status: MotionAuthorizationStatus
    private let afterRequest: MotionAuthorizationStatus
    private let requestThrows: Bool
    private(set) var requestCallCount = 0

    init(
        status: MotionAuthorizationStatus = .notDetermined,
        afterRequest: MotionAuthorizationStatus = .authorized,
        requestThrows: Bool = false
    ) {
        self.status = status
        self.afterRequest = afterRequest
        self.requestThrows = requestThrows
    }

    func authorizationStatus() -> MotionAuthorizationStatus { status }

    func requestAuthorization() throws -> MotionAuthorizationStatus {
        requestCallCount += 1
        if requestThrows { throw FakeMotionAuthorizerError.interrupted }
        status = afterRequest
        return status
    }
}

enum FakeMotionAuthorizerError: Error, Sendable {
    case interrupted
}
