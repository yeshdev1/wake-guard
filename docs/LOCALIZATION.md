# Localization (WG-206)

## How strings are externalized

WakeGuard's UI is SwiftUI. `Text("Delete all data")` is a **`LocalizedStringKey`** — the literal is the
localization *key*, looked up in the bundle at runtime — so user-facing strings are **already
externalized**; no `NSLocalizedString` boilerplate is required. Notification bodies that aren't views use
`String(localized:)` / `NSLocalizedString` explicitly.

The only `Text(verbatim:)` in the app is `EventTitleText` (WG-148), which renders **untrusted** calendar
titles verbatim on purpose (so a hostile title can't be interpreted as a key or markup). This is
intentional and pinned by a test.

## String Catalog

`Localizable.xcstrings` (a String Catalog) is bundled with the app. Xcode extracts every `LocalizedStringKey`
into it at build time; translators add locales there. The base (`sourceLanguage`) is English.

## Pluralization & interpolation

- Counts use locale-formatted numbers (`Int.formatted(.number)`), never `String(count)`, so grouping and
  digits follow the locale. See `LocalizedText.alarmCount`.
- Plural *rules* (one/other/…) live in the String Catalog's plural variations per language — not in Swift
  `if count == 1` branches, which don't cover languages with more plural categories. `LocalizedText` is a
  safe code fallback for non-view contexts.

## Permission strings

The five permission usage descriptions are defined in `project.yml` (`INFOPLIST_KEY_NS…UsageDescription`)
as the English base. They are localized per market by adding an `InfoPlist.xcstrings` String Catalog with
translations — a release/translation step. The base strings are present and non-empty (pinned by a test).
