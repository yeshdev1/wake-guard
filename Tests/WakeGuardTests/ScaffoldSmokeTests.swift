import XCTest
@testable import WakeGuard

/// WG-003 structural smoke tests: prove the app target builds, the composition
/// root constructs, and every ARCHITECTURE §2 feature module is compiled into
/// the app target (ADR-003 single-target membership guard — this checks target
/// membership, not domain isolation, which WG-004's lint will enforce).
/// Behavioral tests arrive with the features they cover.
final class ScaffoldSmokeTests: XCTestCase {

    @MainActor
    func testCompositionRootConstructs() {
        // The @main app's root view builds with no business logic wired yet.
        _ = RootView()
    }

    func testFeatureModuleNamespacesLinkIntoAppTarget() {
        // One reference per feature module. If a feature folder is dropped from
        // the app target, this fails to compile — a cheap structure guard.
        _ = (
            DesignSystem.self,
            AlarmDomain.self, AlarmApplication.self, AlarmInfrastructure.self,
            MotionDomain.self, MotionInfrastructure.self,
            TravelDomain.self, TravelInfrastructure.self,
            HealthDomain.self, HealthInfrastructure.self,
            CalendarInfrastructure.self,
            AIApplication.self, AIInfrastructure.self,
            PrivacySecurity.self, Observability.self
        )
    }
}
