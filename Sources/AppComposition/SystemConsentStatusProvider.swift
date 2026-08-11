import Foundation

#if canImport(UserNotifications)
    import UserNotifications
#endif
#if canImport(CoreMotion)
    import CoreMotion
#endif
#if canImport(EventKit)
    import EventKit
#endif
#if canImport(HealthKit)
    import HealthKit
#endif

/// Pure mapping from each OS authorization enum onto the framework-independent `ConsentStatus` (WG-180).
/// Kept separate from the framework reads so the mapping is unit-testable without touching a live
/// framework — a test passes the raw OS enum values directly.
enum ConsentStatusMapping {
    static func map(alarm: AlarmAuthorizationState) -> ConsentStatus {
        switch alarm {
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        }
    }

    /// Cloud AI is not an OS permission: it is granted only when the user has separately consented **and**
    /// a token is stored (both off by default), else not-determined (#34/#35).
    static func mapCloudAI(consented: Bool, hasToken: Bool) -> ConsentStatus {
        consented && hasToken ? .granted : .notDetermined
    }

    #if canImport(UserNotifications)
        static func map(notifications status: UNAuthorizationStatus) -> ConsentStatus {
            switch status {
            case .authorized, .provisional, .ephemeral: .granted
            case .denied: .denied
            case .notDetermined: .notDetermined
            @unknown default: .notDetermined
            }
        }
    #endif

    /// Location maps the app's domain `LocationAuthorizationStatus` (from the significant-location source),
    /// **not** a CoreLocation type — so CoreLocation stays confined to the one WG-102 adapter.
    static func map(location status: LocationAuthorizationStatus) -> ConsentStatus {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        }
    }

    #if canImport(CoreMotion)
        static func map(motion status: CMAuthorizationStatus) -> ConsentStatus {
            switch status {
            case .authorized: .granted
            case .denied: .denied
            case .restricted: .restricted
            case .notDetermined: .notDetermined
            @unknown default: .notDetermined
            }
        }
    #endif

    #if canImport(EventKit)
        static func map(calendar status: EKAuthorizationStatus) -> ConsentStatus {
            switch status {
            case .authorized, .fullAccess: .granted
            // Read access is what the app needs; write-only can't read events, so treat it as denied.
            case .writeOnly: .denied
            case .denied: .denied
            case .restricted: .restricted
            case .notDetermined: .notDetermined
            @unknown default: .notDetermined
            }
        }
    #endif
}

/// The production `ConsentStatusProviding` (WG-180): reports each category's live status by reading the OS
/// authorization — **status reads only, never a prompt**, so it holds no alarm authority and toggling
/// nothing here changes whether an alarm rings (#9). Composed only in `production()`; the in-memory graph
/// uses `FixedConsentStatusProvider` so tests/previews stay hermetic. Health read-status is intentionally
/// coarse — HealthKit hides read authorization, so it reports `.notDetermined` when available (never a
/// prompt) and `.unavailable` otherwise, honestly rather than guessing.
struct SystemConsentStatusProvider: ConsentStatusProviding {
    let alarm: any AlarmManagerAdapter
    let settings: any SettingsRepository
    let cloudToken: any CloudTokenStore
    /// The significant-location source (WG-102) — its `authorizationStatus()` returns the domain
    /// `LocationAuthorizationStatus`, so this provider reads location **consent status only** and never
    /// imports CoreLocation (the coordinate-handling stays confined to that one adapter, #41).
    let location: any SignificantLocationSource

    func status(for category: ConsentCategory) async -> ConsentStatus {
        switch category {
        case .alarm:
            return ConsentStatusMapping.map(alarm: await alarm.authorizationState())
        case .cloudAI:
            let consented = (try? await settings.settings())?.cloudAIConsented ?? false
            return ConsentStatusMapping.mapCloudAI(
                consented: consented, hasToken: await cloudToken.hasToken())
        case .notifications:
            return await notificationStatus()
        case .location:
            return ConsentStatusMapping.map(location: await location.authorizationStatus())
        case .motion:
            return motionStatus()
        case .calendar:
            return calendarStatus()
        case .health:
            return healthStatus()
        }
    }

    private func notificationStatus() async -> ConsentStatus {
        #if canImport(UserNotifications)
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return ConsentStatusMapping.map(notifications: settings.authorizationStatus)
        #else
            return .unavailable
        #endif
    }

    private func motionStatus() -> ConsentStatus {
        #if canImport(CoreMotion)
            return ConsentStatusMapping.map(motion: CMMotionActivityManager.authorizationStatus())
        #else
            return .unavailable
        #endif
    }

    private func calendarStatus() -> ConsentStatus {
        #if canImport(EventKit)
            return ConsentStatusMapping.map(calendar: EKEventStore.authorizationStatus(for: .event))
        #else
            return .unavailable
        #endif
    }

    private func healthStatus() -> ConsentStatus {
        #if canImport(HealthKit)
            return HKHealthStore.isHealthDataAvailable() ? .notDetermined : .unavailable
        #else
            return .unavailable
        #endif
    }
}

/// A hermetic `ConsentStatusProviding` for the in-memory graph (tests/previews): every category returns a
/// fixed status without touching any OS framework, so the composed graph never prompts or reads hardware.
struct FixedConsentStatusProvider: ConsentStatusProviding {
    var status: ConsentStatus = .notDetermined
    func status(for category: ConsentCategory) async -> ConsentStatus { status }
}
