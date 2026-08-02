/// An in-memory `SettingsRepository` — the production in-memory counterpart to
/// `CoreDataSettingsRepository`, sharing the same WG-012 contract. Useful for
/// SwiftUI previews and as a default before the Core Data stack is wired in
/// (WG-018).
actor InMemorySettingsRepository: SettingsRepository {
    private var stored: AppSettings?

    init(_ initial: AppSettings? = nil) {
        stored = initial
    }

    func settings() async throws -> AppSettings {
        stored ?? .default
    }

    func save(_ settings: AppSettings) async throws {
        stored = settings
    }
}
