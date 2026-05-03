import Foundation
import Security

public actor KeychainWebexStore: WebexClientRegistryStore {
    private let service: String
    private let storage: KeychainWebexStoreStorage
    private let serviceLock: KeychainWebexStoreServiceLock
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var resolvedAutomaticStorage: KeychainWebexStoreStorage?

    public init() {
        self.init(service: KeychainWebexStoreService.defaultService())
    }

    public init(
        service: String,
        storage: KeychainWebexStoreStorage = .automatic
    ) {
        self.service = service
        self.storage = storage
        self.serviceLock = KeychainWebexStoreLockRegistry.shared.lock(for: service)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.resolvedAutomaticStorage = nil
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

    public func addAccount(
        accountID: WebexAccountID,
        credential: WebexCredentialRecord,
        metadata: WebexAccountMetadata
    ) async throws {
        try Task.checkCancellation()
        try withServiceLock {
            try addAccountLocked(accountID: accountID, credential: credential, metadata: metadata)
        }
    }

    public func removeAccount(accountID: WebexAccountID) async throws {
        try Task.checkCancellation()
        try withServiceLock {
            try removeAccountLocked(accountID: accountID)
        }
    }

    public func deleteAccountIndex() async throws {
        try delete(account: account(.accountIndex, accountID: nil))
    }

    private func loadRecord<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        for queryStorage in activeStorages() {
            var result: CFTypeRef?
            let status = SecItemCopyMatching(loadQuery(account: account, storage: queryStorage) as CFDictionary, &result)

            if status == errSecItemNotFound {
                return nil
            }

            if storage.shouldFallbackToLegacy(after: status, from: queryStorage) {
                resolvedAutomaticStorage = .legacy
                return try loadRecord(type, account: account)
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

        return nil
    }

    private func saveRecord<T: Encodable>(_ record: T, account: String) throws {
        let data: Data
        do {
            data = try encoder.encode(record)
        } catch {
            throw KeychainWebexStoreError.encodingFailed(account: account)
        }

        for queryStorage in activeStorages() {
            let status = saveData(data, account: account, storage: queryStorage)
            if status == errSecSuccess {
                return
            }

            if storage.shouldFallbackToLegacy(after: status, from: queryStorage) {
                resolvedAutomaticStorage = .legacy
                let retryStatus = saveData(data, account: account, storage: .legacy)
                if retryStatus == errSecSuccess {
                    return
                }

                throw KeychainWebexStoreError.unhandledStatus(
                    operation: "save",
                    status: retryStatus,
                    service: service,
                    account: account
                )
            }

            throw KeychainWebexStoreError.unhandledStatus(
                operation: "save",
                status: status,
                service: service,
                account: account
            )
        }
    }

    private func saveData(
        _ data: Data,
        account: String,
        storage queryStorage: KeychainWebexStoreStorage
    ) -> OSStatus {
        let updateStatus = SecItemUpdate(
            baseQuery(account: account, storage: queryStorage) as CFDictionary,
            updateAttributes(data: data) as CFDictionary
        )

        guard updateStatus == errSecItemNotFound else {
            return updateStatus
        }

        let addStatus = SecItemAdd(addQuery(account: account, data: data, storage: queryStorage) as CFDictionary, nil)
        guard addStatus == errSecDuplicateItem else {
            return addStatus
        }

        return SecItemUpdate(
            baseQuery(account: account, storage: queryStorage) as CFDictionary,
            updateAttributes(data: data) as CFDictionary
        )
    }

    private func delete(account: String) throws {
        for queryStorage in activeStorages() {
            let status = SecItemDelete(baseQuery(account: account, storage: queryStorage) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                if storage.shouldFallbackToLegacy(after: status, from: queryStorage) {
                    resolvedAutomaticStorage = .legacy
                    try delete(account: account)
                    return
                }

                throw KeychainWebexStoreError.unhandledStatus(
                    operation: "delete",
                    status: status,
                    service: service,
                    account: account
                )
            }
        }
    }

    private func activeStorages() -> [KeychainWebexStoreStorage] {
        switch storage {
        case .automatic:
            if let resolvedAutomaticStorage {
                return [resolvedAutomaticStorage]
            }

            let detectedStorage = Self.detectAutomaticStorage(service: service)
            resolvedAutomaticStorage = detectedStorage
            return [detectedStorage]
        case .dataProtection, .legacy:
            return storage.queryStorages
        }
    }

    private static func detectAutomaticStorage(service: String) -> KeychainWebexStoreStorage {
        let account = "storage-probe:\(UUID().uuidString)"
        let query = KeychainWebexStoreQuery(service: service, account: account, storage: .dataProtection)
        let status = SecItemAdd(query.add(data: Data("probe".utf8)) as CFDictionary, nil)

        if status == errSecSuccess {
            _ = SecItemDelete(query.base as CFDictionary)
            return .dataProtection
        }

        if KeychainWebexStoreStorage.isMissingEntitlement(status) {
            return .legacy
        }

        return .dataProtection
    }

    private func withServiceLock<T>(_ operation: () throws -> T) throws -> T {
        try serviceLock.withLock(operation)
    }

    private func addAccountLocked(
        accountID: WebexAccountID,
        credential: WebexCredentialRecord,
        metadata: WebexAccountMetadata
    ) throws {
        let existingAccountIDs = try loadAccountIDsLocked()
        try WebexAccountDuplicateDetector.validateNoDuplicate(
            candidateCredential: credential,
            candidateMetadata: metadata,
            existingAccountIDs: existingAccountIDs,
            loadCredential: { accountID in
                try loadRecord(WebexCredentialRecord.self, account: account(.credential, accountID: accountID))
            },
            loadMetadata: { accountID in
                try loadRecord(WebexAccountMetadata.self, account: account(.metadata, accountID: accountID))
            }
        )

        do {
            try saveRecord(credential, account: account(.credential, accountID: accountID))
            try saveRecord(metadata, account: account(.metadata, accountID: accountID))

            var accountIDs = existingAccountIDs
            accountIDs.append(accountID)
            try saveAccountIDsLocked(accountIDs)
        } catch {
            cleanupPartiallyAddedAccountLocked(accountID)
            throw error
        }
    }

    private func removeAccountLocked(accountID: WebexAccountID) throws {
        let accountIDs = try loadAccountIDsLocked()
        let remainingAccountIDs = accountIDs.filter { $0 != accountID }
        if remainingAccountIDs != accountIDs {
            try saveAccountIDsLocked(remainingAccountIDs)
        }

        var firstDeleteError: Error?
        do {
            try delete(account: account(.credential, accountID: accountID))
        } catch {
            firstDeleteError = firstDeleteError ?? error
        }

        do {
            try delete(account: account(.token, accountID: accountID))
        } catch {
            firstDeleteError = firstDeleteError ?? error
        }

        do {
            try delete(account: account(.metadata, accountID: accountID))
        } catch {
            firstDeleteError = firstDeleteError ?? error
        }

        if let firstDeleteError {
            throw firstDeleteError
        }
    }

    private func cleanupPartiallyAddedAccountLocked(_ accountID: WebexAccountID) {
        do {
            let accountIDs = try loadAccountIDsLocked()
            let remainingAccountIDs = accountIDs.filter { $0 != accountID }
            if remainingAccountIDs != accountIDs {
                try saveAccountIDsLocked(remainingAccountIDs)
            }
        } catch {
        }

        do {
            try delete(account: account(.credential, accountID: accountID))
        } catch {
        }

        do {
            try delete(account: account(.token, accountID: accountID))
        } catch {
        }

        do {
            try delete(account: account(.metadata, accountID: accountID))
        } catch {
        }
    }

    private func loadAccountIDsLocked() throws -> [WebexAccountID] {
        try loadRecord([WebexAccountID].self, account: account(.accountIndex, accountID: nil)) ?? []
    }

    private func saveAccountIDsLocked(_ accountIDs: [WebexAccountID]) throws {
        var seenAccountIDs = Set<WebexAccountID>()
        let deduplicatedAccountIDs = accountIDs.filter { accountID in
            seenAccountIDs.insert(accountID).inserted
        }
        try saveRecord(deduplicatedAccountIDs, account: account(.accountIndex, accountID: nil))
    }

    private func account(_ kind: RecordKind, accountID: WebexAccountID?) -> String {
        switch kind {
        case .credential, .token, .metadata:
            return "\(kind.rawValue):\(accountID!.rawValue)"
        case .accountIndex:
            return kind.rawValue
        }
    }

    private func baseQuery(
        account: String,
        storage queryStorage: KeychainWebexStoreStorage
    ) -> [String: Any] {
        keychainQuery(account: account, storage: queryStorage).base
    }

    private func loadQuery(
        account: String,
        storage queryStorage: KeychainWebexStoreStorage
    ) -> [String: Any] {
        keychainQuery(account: account, storage: queryStorage).load
    }

    private func addQuery(
        account: String,
        data: Data,
        storage queryStorage: KeychainWebexStoreStorage
    ) -> [String: Any] {
        keychainQuery(account: account, storage: queryStorage).add(data: data)
    }

    private func updateAttributes(data: Data) -> [String: Any] {
        [
            kSecValueData as String: data
        ]
    }

    private func keychainQuery(
        account: String,
        storage queryStorage: KeychainWebexStoreStorage
    ) -> KeychainWebexStoreQuery {
        KeychainWebexStoreQuery(service: service, account: account, storage: queryStorage)
    }

    private enum RecordKind: String {
        case credential
        case token
        case metadata
        case accountIndex = "account-index"
    }
}

public enum KeychainWebexStoreStorage: Equatable, Sendable {
    case automatic
    case dataProtection
    case legacy

    var queryStorages: [KeychainWebexStoreStorage] {
        switch self {
        case .automatic:
            return [.dataProtection, .legacy]
        case .dataProtection:
            return [.dataProtection]
        case .legacy:
            return [.legacy]
        }
    }

    func shouldFallbackToLegacy(
        after status: OSStatus,
        from attemptedStorage: KeychainWebexStoreStorage
    ) -> Bool {
        self == .automatic &&
            attemptedStorage == .dataProtection &&
            Self.isMissingEntitlement(status)
    }

    static func isMissingEntitlement(_ status: OSStatus) -> Bool {
        status == OSStatus(-34018) || status == OSStatus(34018)
    }
}

struct KeychainWebexStoreQuery {
    let service: String
    let account: String
    let storage: KeychainWebexStoreStorage

    var base: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if storage == .dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    var load: [String: Any] {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    func add(data: Data) -> [String: Any] {
        var query = base
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData as String] = data
        return query
    }
}

final class KeychainWebexStoreServiceLock {
    private let lock = NSLock()

    func withLock<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer {
            lock.unlock()
        }

        try Task.checkCancellation()
        return try operation()
    }
}

private final class KeychainWebexStoreLockRegistry {
    static let shared = KeychainWebexStoreLockRegistry()

    private let lock = NSLock()
    private var locks: [String: KeychainWebexStoreServiceLock] = [:]

    func lock(for service: String) -> KeychainWebexStoreServiceLock {
        lock.lock()
        defer {
            lock.unlock()
        }

        if let existingLock = locks[service] {
            return existingLock
        }

        let serviceLock = KeychainWebexStoreServiceLock()
        locks[service] = serviceLock
        return serviceLock
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
