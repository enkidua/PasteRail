import Foundation
import Security
import XCTest
@testable import PasteRail

final class KeychainIntegrationTests: XCTestCase {
    func testConcurrentInitialCreationUsesOneStableKey() async throws {
        guard ProcessInfo.processInfo.environment["PASTERAIL_RUN_KEYCHAIN_TESTS"] == "1" else {
            throw XCTSkip("Set PASTERAIL_RUN_KEYCHAIN_TESTS=1 for signed Keychain integration testing.")
        }
        let suffix = UUID().uuidString
        let service = "io.pasterail.tests.\(suffix)"
        let account = "concurrent"
        defer { delete(service: service, account: account) }
        let store = KeychainEncryptionKeyStore(service: service, account: account)
        let keys = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<8 {
                group.addTask { try store.loadOrCreateKey() }
            }
            var values: [Data] = []
            for try await value in group { values.append(value) }
            return values
        }
        XCTAssertEqual(Set(keys).count, 1)
        XCTAssertEqual(keys.first?.count, 32)
    }

    private func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
