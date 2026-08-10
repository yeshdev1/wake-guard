import SwiftUI

/// Renders an **untrusted** event title **verbatim** (WG-148). `Text(verbatim:)` never interprets the
/// string as Markdown or a localization key, so a hostile title — Markdown, control/RTL characters, or a
/// fake "SYSTEM:" instruction — is shown as inert plain text: it can neither reformat the UI nor be read
/// as an instruction. Titles are display-only and never reach a model (redacted away, WG-140).
struct EventTitleText: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
    }
}
