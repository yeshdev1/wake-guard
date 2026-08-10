import SwiftUI

/// The wellness disclaimer + safety copy (WG-128), shown wherever wellness content appears. States the
/// **wellness, not medical** scope, that figures are estimates, and that urgent concerns are out of
/// scope. Design-system only, VoiceOver-labelled, no color-only signal; holds no alarm authority.
struct WellnessDisclaimerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Label(WellnessSafetyCopy.scope, systemImage: "info.circle")
                .accessibilityIdentifier("wellnessScope")
            Label(WellnessSafetyCopy.urgentSymptoms, systemImage: "cross.case")
                .accessibilityIdentifier("wellnessUrgent")
            Text(WellnessSafetyCopy.estimatesNotClinical)
                .accessibilityIdentifier("wellnessEstimateNote")
        }
        .font(DesignSystem.Typography.caption)
        .foregroundStyle(DesignSystem.Colors.secondaryText)
        .padding(DesignSystem.Spacing.lg)
        .accessibilityElement(children: .combine)
    }
}
