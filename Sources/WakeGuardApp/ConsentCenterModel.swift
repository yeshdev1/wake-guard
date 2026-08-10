import Foundation
import Observation

/// Drives the permission & consent center (WG-180): for **every** category — alarm, notifications, motion,
/// location, health, calendar, and cloud AI, each **separate** — it pairs the static purpose + revocation
/// guidance with the live status from the injected provider. It only reads status; it holds **no alarm
/// authority** and toggling nothing here affects whether an alarm rings (#9).
@MainActor
@Observable
final class ConsentCenterModel {
    private(set) var states: [ConsentCategoryState] = []

    private let provider: any ConsentStatusProviding

    init(provider: any ConsentStatusProviding) {
        self.provider = provider
    }

    /// Refresh every category's live status. Total and non-throwing — an unknown status degrades to a safe
    /// display value, never a crash.
    func refresh() async {
        var result: [ConsentCategoryState] = []
        for info in ConsentCopy.allInfo {
            let status = await provider.status(for: info.category)
            result.append(ConsentCategoryState(info: info, status: status))
        }
        states = result
    }
}
