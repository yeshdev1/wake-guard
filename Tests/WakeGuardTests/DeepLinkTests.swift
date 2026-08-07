import XCTest

@testable import WakeGuard

/// WG-049: deep-link parsing + resolution. Verifies the parser is total (every URL maps to a
/// route, and anything malformed / unknown / over-long is `.unknown`), and that resolving a route
/// only ever *presents a screen* or shows a safe error — it never mutates an alarm (#7), and a
/// stale/unknown id or unsupported target yields a safe message, not a wrong screen.
@MainActor
final class DeepLinkTests: XCTestCase {

    private let ids = DeterministicIDGenerator(seed: 49)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Parser (pure, total)

    private func route(_ string: String) throws -> DeepLinkRoute {
        DeepLinkParser.route(for: try XCTUnwrap(URL(string: string)))
    }

    func testParsesAlarmLink() throws {
        let uuid = UUID()
        XCTAssertEqual(try route("wakeguard://alarm/\(uuid.uuidString)"), .alarm(AlarmID(uuid)))
    }

    func testParsesProposalLink() throws {
        let uuid = UUID()
        XCTAssertEqual(try route("wakeguard://proposal/\(uuid.uuidString)"), .proposal(uuid))
    }

    func testSchemeAndHostAreCaseInsensitive() throws {
        let uuid = UUID()
        XCTAssertEqual(try route("WAKEGUARD://Alarm/\(uuid.uuidString)"), .alarm(AlarmID(uuid)))
    }

    func testWrongSchemeIsUnknown() throws {
        XCTAssertEqual(try route("https://alarm/\(UUID().uuidString)"), .unknown)
    }

    func testUnknownHostIsUnknown() throws {
        XCTAssertEqual(try route("wakeguard://settings/\(UUID().uuidString)"), .unknown)
    }

    func testInvalidUUIDIsUnknown() throws {
        XCTAssertEqual(try route("wakeguard://alarm/not-a-uuid"), .unknown)
    }

    func testMissingIDIsUnknown() throws {
        XCTAssertEqual(try route("wakeguard://alarm"), .unknown)
        XCTAssertEqual(try route("wakeguard://alarm/"), .unknown)
    }

    func testExtraPathSegmentsAreUnknown() throws {
        // A crafted link with extra segments must not be coerced into a target.
        XCTAssertEqual(try route("wakeguard://alarm/\(UUID().uuidString)/extra"), .unknown)
    }

    // MARK: - Resolver (never mutates)

    private func makeAlarm(id: AlarmID) throws -> Alarm {
        let schedule = ScheduleRule.weekly(
            WeeklySchedule(
                days: try WeekdaySet(Set(Weekday.allCases)),
                time: try TimeOfDay(hour: 7, minute: 0),
                timeZone: try IANATimeZone(identifier: "UTC")))
        let epoch = Date(timeIntervalSince1970: 0)
        return try Alarm(
            id: id, label: "wake", schedule: schedule, createdAt: epoch, updatedAt: epoch,
            revision: 3)
    }

    private func makeEnvironment() throws -> AppEnvironment {
        try AppEnvironment.inMemory(clock: TestClock(now: now), identifierGenerator: ids)
    }

    func testOpeningAnAlarmLinkPresentsItWithoutMutating() async throws {
        let env = try makeEnvironment()
        let id = AlarmID(ids.next())
        try await env.alarmRepository.save(makeAlarm(id: id))

        let model = DeepLinkModel()
        await model.open(.alarm(id), using: env)

        XCTAssertEqual(model.alarmToEdit?.id, id, "the alarm is presented for editing")
        XCTAssertNil(model.errorMessage)
        // No auto-mutation (#7): merely opening the link leaves the stored alarm untouched.
        let stored = try await env.alarmRepository.alarm(id: id)
        XCTAssertEqual(stored?.revision, 3, "opening a link must not change the alarm")
    }

    func testStaleAlarmLinkShowsSafeError() async throws {
        let env = try makeEnvironment()
        let model = DeepLinkModel()
        await model.open(.alarm(AlarmID(ids.next())), using: env)  // never saved
        XCTAssertNil(model.alarmToEdit)
        XCTAssertEqual(model.errorMessage, "That alarm no longer exists.")
    }

    func testProposalLinkIsNotAvailable() async throws {
        let env = try makeEnvironment()
        let model = DeepLinkModel()
        await model.open(.proposal(UUID()), using: env)
        XCTAssertNil(model.alarmToEdit, "no proposal screen exists; never invent one")
        XCTAssertFalse(model.errorMessage?.isEmpty ?? true)
    }

    func testUnknownRouteShowsSafeError() async {
        let model = DeepLinkModel()
        await model.open(.unknown, using: nil)
        XCTAssertNil(model.alarmToEdit)
        XCTAssertNotNil(model.errorMessage)
    }

    func testASecondLinkReplacesTheFirstResult() async throws {
        let env = try makeEnvironment()
        let id = AlarmID(ids.next())
        try await env.alarmRepository.save(makeAlarm(id: id))
        let model = DeepLinkModel()

        await model.open(.unknown, using: env)  // sets an error
        XCTAssertNotNil(model.errorMessage)

        await model.open(.alarm(id), using: env)  // a newer link supersedes it
        XCTAssertEqual(model.alarmToEdit?.id, id)
        XCTAssertNil(model.errorMessage, "a newer link clears the prior link's error")
    }
}
