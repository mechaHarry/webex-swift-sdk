import Foundation
import Security

public actor KeychainWebexStore: WebexCredentialStore, WebexTokenStore, WebexAccountMetadataStore, WebexAccountIndexStore {
    private let service: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        self.init(service: KeychainWebexStoreService.defaultService())
    }

    public init(service: String) {
        self.service = service
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func loadCredential(for accountID: WebexAccountID) async throws -> WebexCredentialRecord? {
        try loadRecord(WebexCredentialRecord.self, account: account(.credential, accountID: accountID))
    }

    public func saveCredential(_ credential: WebexCredentialRecord, for accountID: WebexAccountID) async throws {
        try saveRecord(credential, account: account(.credential, accountID: accountID))
    }

    public func deleteCredential(for accountID: WebexAccountID) async throws {
        try delete(account: account(.credential, accountID: accountID))
    }

    public func loadTokenRecord(for accountID: WebexAccountID) async throws -> WebexTokenRecord? {
        try loadRecord(WebexTokenRecord.self, account: account(.token, accountID: accountID))
    }

    public func saveTokenRecord(_ tokenRecord: WebexTokenRecord, for accountID: WebexAccountID) async throws {
        try saveRecord(tokenRecord, account: account(.token, accountID: accountID))
    }

    public func deleteTokenRecord(for accountID: WebexAccountID) async throws {
        try delete(account: account(.token, accountID: accountID))
    }

    public func loadMetadata(for accountID: WebexAccountID) async throws -> WebexAccountMetadata? {
        try loadRecord(WebexAccountMetadata.self, account: account(.metadata, accountID: accountID))
    }

    public func saveMetadata(_ metadata: WebexAccountMetadata, for accountID: WebexAccountID) async throws {
        try saveRecord(metadata, account: account(.metadata, accountID: accountID))
    }

    public func deleteMetadata(for accountID: WebexAccountID) async throws {
        try delete(account: account(.metadata, accountID: accountID))
    }

    public func loadAccountIDs() async throws -> [WebexAccountID] {
        try loadRecord([WebexAccountID].self, account: account(.accountIndex, accountID: nil)) ?? []
    }

    public func saveAccountIDs(_ accountIDs: [WebexAccountID]) async throws {
        var seenAccountIDs = Set<WebexAccountID>()
        let deduplicatedAccountIDs = accountIDs.filter { accountID in
            seenAccountIDs.insert(accountID).inserted
        }
        try saveRecord(deduplicatedAccountIDs, account: account(.accountIndex, accountID: nil))
    }

    public func deleteAccountIndex() async throws {
        try delete(account: account(.accountIndex, accountID: nil))
    }

    private func loadRecord<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(loadQuery(account: account) as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainWebexStoreError.unhandledStatus(
                operation: "load",
                status: status,
                service: service,
                account: account
            )
        }

        guard let data = result as? Data else {
            throw KeychainWebexStoreError.unexpectedItemData(service: service, account: account)
        }

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw KeychainWebexStoreError.decodingFailed(account: account)
        }
    }

    private func saveRecord<T: Encodable>(_ record: T, account: String) throws {
        let data: Data
        do {
            data = try encoder.encode(record)
        } catch {
            throw KeychainWebexStoreError.encodingFailed(account: account)
        }

        let updateStatus = SecItemUpdate(
            baseQuery(account: account) as CFDictionary,
            updateAttributes(data: data) as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            let addStatus = SecItemAdd(addQuery(account: account, data: data) as CFDictionary, nil)
            if addStatus == errSecSuccess {
                return
            }

            if addStatus == errSecDuplicateItem {
                let retryStatus = SecItemUpdate(
                    baseQuery(account: account) as CFDictionary,
                    updateAttributes(data: data) as CFDictionary
                )
                guard retryStatus == errSecSuccess else {
                    throw KeychainWebexStoreError.unhandledStatus(
                        operation: "save",
                        status: retryStatus,
                        service: service,
                        account: account
                    )
                }
                return
            }

            throw KeychainWebexStoreError.unhandledStatus(
                operation: "save",
                status: addStatus,
                service: service,
                account: account
            )
        default:
            throw KeychainWebexStoreError.unhandledStatus(
                operation: "save",
                status: updateStatus,
                service: service,
                account: account
            )
        }
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainWebexStoreError.unhandledStatus(
                operation: "delete",
                status: status,
                service: service,
                account: account
            )
        }
    }

    private func account(_ kind: RecordKind, accountID: WebexAccountID?) -> String {
        switch kind {
        case .credential, .token, .metadata:
            return "\(kind.rawValue):\(accountID!.rawValue)"
        case .accountIndex:
            return kind.rawValue
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func loadQuery(account: String) -> [String: Any] {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    private func addQuery(account: String, data: Data) -> [String: Any] {
        var query = baseQuery(account: account)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData as String] = data
        return query
    }

    private func updateAttributes(data: Data) -> [String: Any] {
        [
            kSecValueData as String: data
        ]
    }

    private enum RecordKind: String {
        case credential
        case token
        case metadata
        case accountIndex = "account-index"
    }
}

enum KeychainWebexStoreService {
    static func defaultService(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        processName: String = ProcessInfo.processInfo.processName,
        executablePath: String? = Bundle.main.executableURL?.path ?? Bundle.main.bundleURL.path
    ) -> String {
        if let bundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleIdentifier.isEmpty {
            return "\(bundleIdentifier).webex-swift-sdk"
        }

        return "process.\(sanitizedProcessName(processName)).\(hostFingerprint(executablePath)).webex-swift-sdk"
    }

    private static func sanitizedProcessName(_ processName: String) -> String {
        let trimmedProcessName = processName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackProcessName = trimmedProcessName.isEmpty ? "unknown-process" : trimmedProcessName
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))

        return String(
            fallbackProcessName.unicodeScalars.map { scalar in
                allowedCharacters.contains(scalar) ? Character(scalar) : "-"
            }
        )
    }

    private static func hostFingerprint(_ executablePath: String?) -> String {
        let normalizedPath = executablePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fingerprintInput = normalizedPath?.isEmpty == false ? normalizedPath! : "unknown-host-path"
        let hash = fingerprintInput.utf8.reduce(UInt64(0xcbf29ce484222325)) { result, byte in
            (result ^ UInt64(byte)) &* 0x100000001b3
        }

        return String(hash, radix: 16)
    }
}

public enum KeychainWebexStoreError: Error, Equatable, Sendable {
    case unhandledStatus(operation: String, status: OSStatus, service: String, account: String)
    case unexpectedItemData(service: String, account: String)
    case encodingFailed(account: String)
    case decodingFailed(account: String)
}

extension KeychainWebexStoreError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unhandledStatus(let operation, let status, _, _):
            return "Keychain \(operation) failed with status \(status)"
        case .unexpectedItemData:
            return "Keychain returned unexpected item data"
        case .encodingFailed:
            return "Keychain record encoding failed"
        case .decodingFailed:
            return "Keychain record decoding failed"
        }
    }
}
