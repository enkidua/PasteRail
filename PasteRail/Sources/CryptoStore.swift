import CryptoKit
import Foundation
import Security

protocol EncryptionKeyStore: Sendable {
    func loadOrCreateKey() throws -> Data
}

enum CryptoStoreError: Error {
    case keychain(OSStatus)
    case invalidKey
    case authenticationFailed
}

struct KeychainEncryptionKeyStore: EncryptionKeyStore {
    private enum KeyReadResult {
        case key(Data)
        case status(OSStatus)
    }
    let service: String
    let account: String

    init(
        service: String = "io.pasterail.PasteRail.storage",
        account: String = "primary-aes-gcm-key"
    ) {
        self.service = service
        self.account = account
    }

    func loadOrCreateKey() throws -> Data {
        switch readKey() {
        case let .key(data):
            return data
        case let .status(status) where status == errSecItemNotFound:
            break
        case let .status(status):
            throw CryptoStoreError.keychain(status)
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let randomStatus = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
        }
        guard randomStatus == errSecSuccess else { throw CryptoStoreError.invalidKey }
        let data = Data(bytes)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecSuccess { return data }
        if addStatus == errSecDuplicateItem {
            switch readKey() {
            case let .key(existing): return existing
            case let .status(status): throw CryptoStoreError.keychain(status)
            }
        }
        throw CryptoStoreError.keychain(addStatus)
    }

    private func readKey() -> KeyReadResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return .status(status) }
        guard let data = item as? Data, data.count == 32 else { return .status(errSecDecode) }
        return .key(data)
    }
}

struct CryptoStore: Sendable {
    private let key: SymmetricKey

    init(keyStore: EncryptionKeyStore) throws {
        let data = try keyStore.loadOrCreateKey()
        guard data.count == 32 else { throw CryptoStoreError.invalidKey }
        key = SymmetricKey(data: data)
    }

    func seal(_ plaintext: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else { throw CryptoStoreError.authenticationFailed }
        return combined
    }

    func open(_ ciphertext: Data) throws -> Data {
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: ciphertext), using: key)
        } catch {
            throw CryptoStoreError.authenticationFailed
        }
    }
}
