import Foundation
import XCTest

@testable import WakeGuard

/// WG-185: Keychain & secret-handling audit. Locks the guarantees that **no keys live in source or
/// `UserDefaults`**, that **cloud tokens are revocable**, and that **logs never contain secrets** (the
/// token is a log-proof `Sensitive`). Source scans are regression pins so a future secret can't slip in.
final class SecretHandlingAuditTests: XCTestCase {

    private func sourcesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    private func swiftFiles() -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: sourcesDirectory(), includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        return files
    }

    private func strippedCode(of file: URL) throws -> String {
        let contents = try String(contentsOf: file, encoding: .utf8)
        var result = ""
        for raw in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") {
                continue
            }
            if let comment = line.range(of: "//") {
                result += line[line.startIndex..<comment.lowerBound] + "\n"
            } else {
                result += line + "\n"
            }
        }
        return result
    }

    // MARK: no keys in source

    func testNoHardcodedSecretsInSource() throws {
        let dangerous = [
            "\"sk-", "\"Bearer ", "-----BEGIN", "\"AKIA", "apiKey = \"", "apiKey: \"",
            "clientSecret = \"", "secretKey = \"", "password = \"",
        ]
        for file in swiftFiles() {
            let code = try strippedCode(of: file)
            for pattern in dangerous {
                XCTAssertFalse(
                    code.contains(pattern),
                    "\(file.lastPathComponent) may contain a hardcoded secret: '\(pattern)'")
            }
        }
    }

    // MARK: no secrets in UserDefaults

    func testNoSecretIsStoredInUserDefaults() throws {
        for file in swiftFiles() {
            let code = try strippedCode(of: file)
            guard code.contains("UserDefaults") else { continue }
            for secretWord in ["token", "secret", "apiKey", "password", "credential"] {
                XCTAssertFalse(
                    code.lowercased().contains(secretWord.lowercased()),
                    "\(file.lastPathComponent) uses UserDefaults near a secret ('\(secretWord)')")
            }
        }
    }

    // MARK: the Keychain store uses the Keychain, not UserDefaults, and never logs

    func testKeychainStoreUsesKeychainNotUserDefaults() throws {
        let file = sourcesDirectory().appendingPathComponent(
            "AIInfrastructure/KeychainCloudTokenStore.swift")
        let code = try strippedCode(of: file)
        XCTAssertTrue(code.contains("SecItem"), "the token store must use the Keychain")
        for forbidden in [
            "UserDefaults", "print(", "os_log", "Logger", "NSLog", "PrivacyLog",
        ] {
            XCTAssertFalse(code.contains(forbidden), "token store must not use '\(forbidden)'")
        }
    }

    // MARK: cloud tokens are revocable

    func testCloudTokenIsRevocable() async {
        let store = InMemoryCloudTokenStore()
        await store.store(Sensitive("cloud-access-token"))
        var hasToken = await store.hasToken()
        XCTAssertTrue(hasToken)

        await store.revoke()
        hasToken = await store.hasToken()
        XCTAssertFalse(hasToken)
        let token = await store.token()
        XCTAssertNil(token)
    }

    // MARK: logs never contain secrets — the token is a log-proof Sensitive

    func testStoredTokenIsLogProof() async throws {
        let store = InMemoryCloudTokenStore(Sensitive("super-secret-token"))
        let stored = await store.token()
        let token = try XCTUnwrap(stored)
        XCTAssertEqual("\(token)", "<redacted>")
        XCTAssertEqual(token.reveal(), "super-secret-token")
    }
}
