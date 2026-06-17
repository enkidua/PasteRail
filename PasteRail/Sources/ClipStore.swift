import AppKit
import CryptoKit
import Darwin
import Foundation

enum ClipStoreFileOperation: Equatable, Sendable {
    case beforeBackupCopy
    case beforeBackupReplace
    case beforeIndexWrite
    case afterCleanupValidation
    case beforeHistoryLimitPersist
}

actor ClipStore {
    static let maximumStoredRecords = 100
    static let maximumPayloadBytes = 20 * 1024 * 1024
    static let maximumStorageBytes: Int64 = 500 * 1024 * 1024

    private struct BootstrapResult {
        var snapshot: Snapshot
        let recoveryMessage: String?
        let indexBytes: Int64
    }

    private struct RecoveryCandidate: Codable {
        let originalPath: String
        let size: Int64
        let discoveredAt: Date
        let eligibleForDeletionAfter: Date
        let expectedKind: String
    }

    private struct PlaintextCleanupEntry: Codable {
        let plaintextRelativePath: String
        let encryptedRelativePath: String
    }

    private struct PlaintextCleanupPlan: Codable {
        let entries: [PlaintextCleanupEntry]
    }

    struct PerformanceMetrics: Sendable {
        let loadDuration: TimeInterval
        var lastSaveDuration: TimeInterval?
        var lastDuplicateDuration: TimeInterval?
        var indexBytes: Int64
    }

    enum StoreError: Error {
        case invalidContainer
        case missingRecord
        case invalidImage
        case corruptIndex(URL)
        case encryptionUnavailable
        case historyLimitReached
        case payloadTooLarge
        case storageLimitReached
    }

    struct Snapshot: Codable, Equatable {
        var schemaVersion = 3
        var records: [ClipRecord] = []
        var queue: [QueueEntry] = []
        var queueIndex = 0
    }

    private let rootURL: URL
    private let payloadsURL: URL
    private let imagesURL: URL
    private let thumbnailsURL: URL
    private let indexURL: URL
    private let backupURL: URL
    private let recoveryURL: URL
    private let crypto: CryptoStore
    private let storageLimitBytes: Int64
    private let persistenceFailureInjector: (@Sendable () throws -> Void)?
    private let fileOperationInjector: (@Sendable (ClipStoreFileOperation) throws -> Void)?
    private var snapshot: Snapshot
    private var digestLookup: [String: UUID] = [:]
    private(set) var performanceMetrics: PerformanceMetrics

    private(set) var recoveryMessage: String?

    init(
        rootURL: URL? = nil,
        keyStore: EncryptionKeyStore = KeychainEncryptionKeyStore(),
        storageLimitBytes: Int64 = ClipStore.maximumStorageBytes,
        persistenceFailureInjector: (@Sendable () throws -> Void)? = nil,
        fileOperationInjector: (@Sendable (ClipStoreFileOperation) throws -> Void)? = nil
    ) throws {
        let loadStarted = CFAbsoluteTimeGetCurrent()
        let fileManager = FileManager.default
        let root: URL
        if let rootURL {
            root = rootURL
        } else {
            guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw StoreError.invalidContainer
            }
            root = support.appendingPathComponent("io.pasterail.PasteRail", isDirectory: true)
        }
        let localPayloadsURL = root.appendingPathComponent("Payloads", isDirectory: true)
        let localImagesURL = root.appendingPathComponent("Images", isDirectory: true)
        let localThumbnailsURL = root.appendingPathComponent("Thumbnails", isDirectory: true)
        let localIndexURL = root.appendingPathComponent("history.enc")
        let localBackupURL = root.appendingPathComponent("history.backup.enc")
        let localRecoveryURL = root.appendingPathComponent("Recovery", isDirectory: true)
        let localCrypto: CryptoStore
        do {
            localCrypto = try CryptoStore(keyStore: keyStore)
        } catch {
            throw StoreError.encryptionUnavailable
        }
        try [root, localPayloadsURL, localImagesURL, localThumbnailsURL, localRecoveryURL].forEach {
            try fileManager.createDirectory(at: $0, withIntermediateDirectories: true)
        }
        let bootstrap = try Self.bootstrap(
            root: root,
            payloadsURL: localPayloadsURL,
            imagesURL: localImagesURL,
            thumbnailsURL: localThumbnailsURL,
            indexURL: localIndexURL,
            backupURL: localBackupURL,
            recoveryURL: localRecoveryURL,
            crypto: localCrypto,
            storageLimitBytes: storageLimitBytes,
            persistenceFailureInjector: persistenceFailureInjector,
            fileOperationInjector: fileOperationInjector
        )

        self.rootURL = root
        payloadsURL = localPayloadsURL
        imagesURL = localImagesURL
        thumbnailsURL = localThumbnailsURL
        indexURL = localIndexURL
        backupURL = localBackupURL
        recoveryURL = localRecoveryURL
        crypto = localCrypto
        self.storageLimitBytes = storageLimitBytes
        self.persistenceFailureInjector = persistenceFailureInjector
        self.fileOperationInjector = fileOperationInjector
        snapshot = bootstrap.snapshot
        recoveryMessage = bootstrap.recoveryMessage
        digestLookup = Dictionary(
            bootstrap.snapshot.records.compactMap { record in record.digest.map { ($0, record.id) } },
            uniquingKeysWith: { first, _ in first }
        )
        performanceMetrics = PerformanceMetrics(
            loadDuration: CFAbsoluteTimeGetCurrent() - loadStarted,
            indexBytes: bootstrap.indexBytes
        )
        try Self.applyPrivatePermissions(to: root)
    }

    private static func bootstrap(
        root: URL,
        payloadsURL: URL,
        imagesURL: URL,
        thumbnailsURL: URL,
        indexURL: URL,
        backupURL: URL,
        recoveryURL: URL,
        crypto: CryptoStore,
        storageLimitBytes: Int64,
        persistenceFailureInjector: (@Sendable () throws -> Void)?,
        fileOperationInjector: (@Sendable (ClipStoreFileOperation) throws -> Void)?
    ) throws -> BootstrapResult {
        let fileManager = FileManager.default
        var snapshot: Snapshot
        var recoveryMessage: String?

        if fileManager.fileExists(atPath: indexURL.path) {
            do {
                snapshot = try decodeSnapshot(crypto: crypto, at: indexURL)
            } catch {
                let corruptURL = recoveryURL.appendingPathComponent("history.corrupt-\(Int(Date().timeIntervalSince1970)).enc")
                try fileManager.copyItem(at: indexURL, to: corruptURL)
                guard fileManager.fileExists(atPath: backupURL.path),
                      let recovered = try? decodeSnapshot(crypto: crypto, at: backupURL) else {
                    throw StoreError.corruptIndex(corruptURL)
                }
                try restoreCurrentIndex(
                    from: backupURL,
                    to: indexURL,
                    expected: recovered,
                    crypto: crypto,
                    fileOperationInjector: fileOperationInjector
                )
                snapshot = recovered
                recoveryMessage = "Clipboard history index was damaged. PasteRail preserved the encrypted file and restored the last backup."
            }
        } else {
            snapshot = try migratePlaintextStoreIfPresent(
                root: root,
                payloadsURL: payloadsURL,
                imagesURL: imagesURL,
                thumbnailsURL: thumbnailsURL,
                indexURL: indexURL,
                recoveryURL: recoveryURL,
                crypto: crypto,
                persistenceFailureInjector: persistenceFailureInjector,
                fileOperationInjector: fileOperationInjector
            ) ?? Snapshot()
        }

        var migratedDigest = false
        for index in snapshot.records.indices where snapshot.records[index].digest == nil {
            let record = snapshot.records[index]
            if let payload = try? loadPayload(record, from: payloadsURL, crypto: crypto) {
                snapshot.records[index].digest = payloadDigest(payload)
                migratedDigest = true
            }
        }
        snapshot.schemaVersion = 3
        if migratedDigest {
            try persistSnapshot(
                snapshot,
                indexURL: indexURL,
                backupURL: backupURL,
                crypto: crypto,
                persistenceFailureInjector: persistenceFailureInjector,
                fileOperationInjector: fileOperationInjector
            )
        }
        do {
            var limited = snapshot
            let removed = try applyLimits(
                to: &limited,
                storageLimitBytes: storageLimitBytes,
                payloadsURL: payloadsURL,
                imagesURL: imagesURL,
                thumbnailsURL: thumbnailsURL
            )
            if !removed.isEmpty {
                try fileOperationInjector?(.beforeHistoryLimitPersist)
                try persistSnapshot(
                    limited,
                    indexURL: indexURL,
                    backupURL: backupURL,
                    crypto: crypto,
                    persistenceFailureInjector: persistenceFailureInjector,
                    fileOperationInjector: fileOperationInjector
                )
                deleteFiles(for: removed, payloadsURL: payloadsURL, imagesURL: imagesURL, thumbnailsURL: thumbnailsURL)
                snapshot = limited
            }
        } catch StoreError.storageLimitReached {
            recoveryMessage = [recoveryMessage, "Stored pinned clipboard records exceed the storage limit. PasteRail preserved them and will reject new records until space is available."]
                .compactMap { $0 }
                .joined(separator: "\n")
        } catch StoreError.historyLimitReached {
            recoveryMessage = [recoveryMessage, "More than 100 stored records are pinned. PasteRail preserved them and will reject new records until records are unpinned or removed."]
                .compactMap { $0 }
                .joined(separator: "\n")
        }

        do {
            try completePendingPlaintextCleanup(
                root: root,
                payloadsURL: payloadsURL,
                imagesURL: imagesURL,
                thumbnailsURL: thumbnailsURL,
                indexURL: indexURL,
                recoveryURL: recoveryURL,
                crypto: crypto,
                fileOperationInjector: fileOperationInjector
            )
        } catch {
            recoveryMessage = [recoveryMessage, "Encrypted history is available, but secure plaintext cleanup could not be completed. It will be retried."]
                .compactMap { $0 }
                .joined(separator: "\n")
        }
        try? writeRecoveryCandidateList(
            snapshot: snapshot,
            payloadsURL: payloadsURL,
            imagesURL: imagesURL,
            thumbnailsURL: thumbnailsURL,
            recoveryURL: recoveryURL
        )

        return BootstrapResult(
            snapshot: snapshot,
            recoveryMessage: recoveryMessage,
            indexBytes: Int64((try? indexURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        )
    }

    private static func decodeSnapshot(crypto: CryptoStore, at url: URL) throws -> Snapshot {
        try JSONDecoder.pasteRail.decode(Snapshot.self, from: crypto.open(Data(contentsOf: url)))
    }

    private static func loadPayload(_ record: ClipRecord, from directory: URL, crypto: CryptoStore) throws -> ClipPayload {
        let encrypted = try Data(contentsOf: directory.appendingPathComponent(record.payloadFile))
        return try JSONDecoder.pasteRail.decode(ClipPayload.self, from: crypto.open(encrypted))
    }

    private static func persistSnapshot(
        _ snapshot: Snapshot,
        indexURL: URL,
        backupURL: URL,
        crypto: CryptoStore,
        persistenceFailureInjector: (@Sendable () throws -> Void)?,
        fileOperationInjector: (@Sendable (ClipStoreFileOperation) throws -> Void)?
    ) throws {
        try persistenceFailureInjector?()
        let data = try crypto.seal(JSONEncoder.pasteRail.encode(snapshot))
        try replaceBackup(
            from: indexURL,
            at: backupURL,
            crypto: crypto,
            fileOperationInjector: fileOperationInjector
        )
        try fileOperationInjector?(.beforeIndexWrite)
        try writePrivate(data, to: indexURL)
    }

    private static func replaceBackup(
        from indexURL: URL,
        at backupURL: URL,
        crypto: CryptoStore,
        fileOperationInjector: (@Sendable (ClipStoreFileOperation) throws -> Void)?
    ) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: indexURL.path) else { return }
        try fileOperationInjector?(.beforeBackupCopy)
        let temporary = backupURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(backupURL.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporary) }
        try fileManager.copyItem(at: indexURL, to: temporary)
        guard fileManager.isReadableFile(atPath: temporary.path) else {
            throw StoreError.corruptIndex(temporary)
        }
        _ = try decodeSnapshot(crypto: crypto, at: temporary)
        try fileOperationInjector?(.beforeBackupReplace)
        guard rename(temporary.path, backupURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func restoreCurrentIndex(
        from backupURL: URL,
        to indexURL: URL,
        expected: Snapshot,
        crypto: CryptoStore,
        fileOperationInjector: (@Sendable (ClipStoreFileOperation) throws -> Void)?
    ) throws {
        let fileManager = FileManager.default
        let temporary = indexURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(indexURL.lastPathComponent).recovery-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporary) }
        try fileManager.copyItem(at: backupURL, to: temporary)
        guard fileManager.isReadableFile(atPath: temporary.path),
              try decodeSnapshot(crypto: crypto, at: temporary) == expected else {
            throw StoreError.corruptIndex(temporary)
        }
        try fileOperationInjector?(.beforeIndexWrite)
        guard rename(temporary.path, indexURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard try decodeSnapshot(crypto: crypto, at: indexURL) == expected else {
            throw StoreError.corruptIndex(indexURL)
        }
    }

    private static func writePrivate(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func records() -> [ClipRecord] {
        snapshot.records
    }

    func queueState() -> ([QueueEntry], Int) {
        (snapshot.queue, snapshot.queueIndex)
    }

    func capture(
        payload: ClipPayload,
        kind: ClipKind,
        title: String,
        searchText: String,
        sourceAppName: String?,
        sourceBundleIdentifier: String?
    ) throws -> ClipRecord {
        guard payload.representations.reduce(0, { $0 + $1.data.count }) <= Self.maximumPayloadBytes else {
            throw StoreError.payloadTooLarge
        }
        let duplicateStarted = CFAbsoluteTimeGetCurrent()
        let digest = Self.payloadDigest(payload)
        if let existingID = digestLookup[digest],
           let existingIndex = snapshot.records.firstIndex(where: { $0.id == existingID }) {
            let previousRecords = snapshot.records
            var existing = snapshot.records.remove(at: existingIndex)
            existing.createdAt = Date()
            existing.sourceAppName = sourceAppName
            existing.sourceBundleIdentifier = sourceBundleIdentifier
            snapshot.records.insert(existing, at: 0)
            do {
                try persist()
            } catch {
                snapshot.records = previousRecords
                throw error
            }
            performanceMetrics.lastDuplicateDuration = CFAbsoluteTimeGetCurrent() - duplicateStarted
            return existing
        }
        if snapshot.records.count >= Self.maximumStoredRecords,
           !snapshot.records.contains(where: { !$0.isPinned }) {
            throw StoreError.historyLimitReached
        }

        let id = UUID()
        let payloadName = "\(id.uuidString).json"
        let payloadURL = payloadsURL.appendingPathComponent(payloadName)
        try atomicWrite(try crypto.seal(JSONEncoder.pasteRail.encode(payload)), to: payloadURL)

        let imageName: String? = nil
        var thumbnailName: String?
        do {
            if kind == .image, let imageData = preferredImageData(in: payload) {
                let decoded = NSImage(data: imageData)
                guard let decoded else { throw StoreError.invalidImage }
                thumbnailName = "\(id.uuidString).png"
                try atomicWrite(try crypto.seal(pngData(from: decoded, maximumDimension: 160)), to: thumbnailsURL.appendingPathComponent(thumbnailName!))
            }
        } catch {
            try? FileManager.default.removeItem(at: payloadURL)
            if let imageName { try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(imageName)) }
            if let thumbnailName { try? FileManager.default.removeItem(at: thumbnailsURL.appendingPathComponent(thumbnailName)) }
            throw error
        }

        let record = ClipRecord(
            id: id,
            kind: kind,
            title: title,
            searchText: searchText,
            createdAt: Date(),
            sourceAppName: sourceAppName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            payloadFile: payloadName,
            imageFile: imageName,
            thumbnailFile: thumbnailName,
            digest: digest,
            isSensitive: false,
            isPinned: false
        )
        let previousSnapshot = snapshot
        snapshot.records.insert(record, at: 0)
        digestLookup[digest] = id
        var recordsToDelete: [ClipRecord] = []
        do {
            recordsToDelete = try Self.applyLimits(
                to: &snapshot,
                storageLimitBytes: storageLimitBytes,
                payloadsURL: payloadsURL,
                imagesURL: imagesURL,
                thumbnailsURL: thumbnailsURL
            )
            if recordsToDelete.contains(where: { $0.id == id }) {
                throw StoreError.storageLimitReached
            }
        } catch {
            snapshot = previousSnapshot
            rebuildDigestLookup()
            try? FileManager.default.removeItem(at: payloadURL)
            if let imageName { try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(imageName)) }
            if let thumbnailName { try? FileManager.default.removeItem(at: thumbnailsURL.appendingPathComponent(thumbnailName)) }
            throw error
        }
        let saveStarted = CFAbsoluteTimeGetCurrent()
        do {
            if !recordsToDelete.isEmpty {
                try fileOperationInjector?(.beforeHistoryLimitPersist)
            }
            try persist()
        } catch {
            snapshot = previousSnapshot
            rebuildDigestLookup()
            try? FileManager.default.removeItem(at: payloadURL)
            if let imageName { try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(imageName)) }
            if let thumbnailName { try? FileManager.default.removeItem(at: thumbnailsURL.appendingPathComponent(thumbnailName)) }
            throw error
        }
        deleteFiles(for: recordsToDelete)
        performanceMetrics.lastSaveDuration = CFAbsoluteTimeGetCurrent() - saveStarted
        return record
    }

    func loadPayload(for record: ClipRecord) throws -> ClipPayload {
        let data = try crypto.open(Data(contentsOf: payloadsURL.appendingPathComponent(record.payloadFile)))
        return try JSONDecoder.pasteRail.decode(ClipPayload.self, from: data)
    }

    func thumbnailData(for record: ClipRecord) -> Data? {
        guard let name = record.thumbnailFile else { return nil }
        guard let encrypted = try? Data(contentsOf: thumbnailsURL.appendingPathComponent(name)),
              let data = try? crypto.open(encrypted) else { return nil }
        return data
    }

    func storageBytes() -> Int64 {
        Self.storageBytes(
            for: snapshot.records,
            payloadsURL: payloadsURL,
            imagesURL: imagesURL,
            thumbnailsURL: thumbnailsURL
        )
    }

    func setPinned(_ id: UUID, pinned: Bool) throws {
        guard let index = snapshot.records.firstIndex(where: { $0.id == id }) else {
            throw StoreError.missingRecord
        }
        let previous = snapshot.records[index].isPinned
        snapshot.records[index].isPinned = pinned
        do {
            try persist()
        } catch {
            snapshot.records[index].isPinned = previous
            throw error
        }
    }

    func enqueue(_ clipIDs: [UUID], plainText: Bool = false) throws {
        try mutateQueue {
            let known = Set(snapshot.records.map(\.id))
            snapshot.queue.append(contentsOf: clipIDs.filter(known.contains).map {
                QueueEntry(id: UUID(), clipID: $0, plainText: plainText)
            })
        }
    }

    func currentQueueEntry() -> QueueEntry? {
        guard snapshot.queue.indices.contains(snapshot.queueIndex) else { return nil }
        return snapshot.queue[snapshot.queueIndex]
    }

    func advanceQueue() throws {
        guard snapshot.queue.indices.contains(snapshot.queueIndex) else { return }
        try mutateQueue { snapshot.queueIndex += 1 }
    }

    func previousQueueEntry() throws {
        try mutateQueue { snapshot.queueIndex = max(0, snapshot.queueIndex - 1) }
    }

    func skipQueueEntry() throws {
        try advanceQueue()
    }

    func restartQueue() throws {
        try mutateQueue { snapshot.queueIndex = 0 }
    }

    func clearQueue() throws {
        try mutateQueue {
            snapshot.queue = []
            snapshot.queueIndex = 0
        }
    }

    func record(id: UUID) -> ClipRecord? {
        snapshot.records.first { $0.id == id }
    }

    private func persist() throws {
        try persistenceFailureInjector?()
        let encoded = try crypto.seal(JSONEncoder.pasteRail.encode(snapshot))
        try Self.replaceBackup(
            from: indexURL,
            at: backupURL,
            crypto: crypto,
            fileOperationInjector: fileOperationInjector
        )
        try fileOperationInjector?(.beforeIndexWrite)
        try atomicWrite(encoded, to: indexURL)
        performanceMetrics.indexBytes = Int64(encoded.count)
    }

    private func mutateQueue(_ mutation: () -> Void) throws {
        let previousQueue = snapshot.queue
        let previousIndex = snapshot.queueIndex
        mutation()
        do {
            try persist()
        } catch {
            snapshot.queue = previousQueue
            snapshot.queueIndex = previousIndex
            throw error
        }
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func applyLimits(
        to snapshot: inout Snapshot,
        storageLimitBytes: Int64,
        payloadsURL: URL,
        imagesURL: URL,
        thumbnailsURL: URL
    ) throws -> [ClipRecord] {
        var removed: [ClipRecord] = []
        while snapshot.records.count > maximumStoredRecords {
            guard let index = snapshot.records.lastIndex(where: { !$0.isPinned }) else {
                throw StoreError.historyLimitReached
            }
            removed.append(snapshot.records.remove(at: index))
        }
        while storageBytes(
            for: snapshot.records,
            payloadsURL: payloadsURL,
            imagesURL: imagesURL,
            thumbnailsURL: thumbnailsURL
        ) > storageLimitBytes {
            guard let index = snapshot.records.lastIndex(where: { !$0.isPinned }) else {
                throw StoreError.storageLimitReached
            }
            removed.append(snapshot.records.remove(at: index))
        }
        normalizeQueue(in: &snapshot, removedIDs: Set(removed.map(\.id)))
        return removed
    }

    private static func storageBytes(
        for records: [ClipRecord],
        payloadsURL: URL,
        imagesURL: URL,
        thumbnailsURL: URL
    ) -> Int64 {
        records.reduce(into: 0) { total, record in
            total += fileSize(payloadsURL.appendingPathComponent(record.payloadFile))
            if let imageFile = record.imageFile {
                total += fileSize(imagesURL.appendingPathComponent(imageFile))
            }
            if let thumbnailFile = record.thumbnailFile {
                total += fileSize(thumbnailsURL.appendingPathComponent(thumbnailFile))
            }
        }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private static func normalizeQueue(in snapshot: inout Snapshot, removedIDs: Set<UUID>) {
        guard !removedIDs.isEmpty else {
            snapshot.queueIndex = min(max(0, snapshot.queueIndex), snapshot.queue.count)
            return
        }
        let removedBeforeIndex = snapshot.queue.prefix(snapshot.queueIndex).filter { removedIDs.contains($0.clipID) }.count
        snapshot.queue.removeAll { removedIDs.contains($0.clipID) }
        snapshot.queueIndex = min(max(0, snapshot.queueIndex - removedBeforeIndex), snapshot.queue.count)
    }

    private func deleteFiles(for records: [ClipRecord]) {
        Self.deleteFiles(for: records, payloadsURL: payloadsURL, imagesURL: imagesURL, thumbnailsURL: thumbnailsURL)
    }

    private static func deleteFiles(
        for records: [ClipRecord],
        payloadsURL: URL,
        imagesURL: URL,
        thumbnailsURL: URL
    ) {
        for record in records {
            try? FileManager.default.removeItem(at: payloadsURL.appendingPathComponent(record.payloadFile))
            if let imageFile = record.imageFile {
                try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(imageFile))
            }
            if let thumbnailFile = record.thumbnailFile {
                try? FileManager.default.removeItem(at: thumbnailsURL.appendingPathComponent(thumbnailFile))
            }
        }
    }

    private func rebuildDigestLookup() {
        digestLookup = Dictionary(
            snapshot.records.compactMap { record in record.digest.map { ($0, record.id) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func writeRecoveryCandidateList(
        snapshot: Snapshot,
        payloadsURL: URL,
        imagesURL: URL,
        thumbnailsURL: URL,
        recoveryURL: URL
    ) throws {
        struct CandidateList: Codable {
            let createdAt: Date
            let minimumGracePeriodDays: Int
            let candidates: [RecoveryCandidate]
        }
        let now = Date()
        let eligible = now.addingTimeInterval(7 * 24 * 60 * 60)
        let expectedPayloads = Set(snapshot.records.map(\.payloadFile))
        let expectedImages = Set(snapshot.records.compactMap(\.imageFile))
        let expectedThumbnails = Set(snapshot.records.compactMap(\.thumbnailFile))
        let candidates = CandidateList(
            createdAt: now,
            minimumGracePeriodDays: 7,
            candidates:
                (try recoveryCandidates(in: payloadsURL, expected: expectedPayloads, kind: "payload", now: now, eligible: eligible))
                + (try recoveryCandidates(in: imagesURL, expected: expectedImages, kind: "original-image", now: now, eligible: eligible))
                + (try recoveryCandidates(in: thumbnailsURL, expected: expectedThumbnails, kind: "thumbnail", now: now, eligible: eligible))
        )
        try writePrivate(
            JSONEncoder.pasteRail.encode(candidates),
            to: recoveryURL.appendingPathComponent("orphan-candidates.json")
        )
    }

    private static func recoveryCandidates(
        in directory: URL,
        expected: Set<String>,
        kind: String,
        now: Date,
        eligible: Date
    ) throws -> [RecoveryCandidate] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            .filter { !expected.contains($0.lastPathComponent) }
            .map {
                RecoveryCandidate(
                    originalPath: $0.path,
                    size: Int64((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0),
                    discoveredAt: now,
                    eligibleForDeletionAfter: eligible,
                    expectedKind: kind
                )
            }
    }

    private static func applyPrivatePermissions(to root: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }

    private static func payloadDigest(_ payload: ClipPayload) -> String {
        var value = Data()
        appendLength(payload.items.count, to: &value)
        for item in payload.items {
            appendLength(item.count, to: &value)
            for representation in item {
                let type = Data(representation.pasteboardType.utf8)
                appendLength(type.count, to: &value)
                value.append(type)
                appendLength(representation.data.count, to: &value)
                value.append(representation.data)
            }
        }
        return SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
    }

    private static func appendLength(_ length: Int, to data: inout Data) {
        var value = UInt64(length).bigEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private static func migratePlaintextStoreIfPresent(
        root: URL,
        payloadsURL: URL,
        imagesURL: URL,
        thumbnailsURL: URL,
        indexURL: URL,
        recoveryURL: URL,
        crypto: CryptoStore,
        persistenceFailureInjector: (@Sendable () throws -> Void)?,
        fileOperationInjector: (@Sendable (ClipStoreFileOperation) throws -> Void)?
    ) throws -> Snapshot? {
        let oldIndex = root.appendingPathComponent("history.json")
        guard FileManager.default.fileExists(atPath: oldIndex.path) else { return nil }
        var migrated = try JSONDecoder.pasteRail.decode(Snapshot.self, from: Data(contentsOf: oldIndex))
        var entries = [PlaintextCleanupEntry(
            plaintextRelativePath: "history.json",
            encryptedRelativePath: "history.enc"
        )]
        for index in migrated.records.indices {
            migrated.records[index].payloadFile = try migratePlaintextFile(
                named: migrated.records[index].payloadFile,
                directoryName: "Payloads",
                directory: payloadsURL,
                root: root,
                crypto: crypto,
                entries: &entries
            )
            if let name = migrated.records[index].imageFile {
                migrated.records[index].imageFile = try migratePlaintextFile(
                    named: name, directoryName: "Images", directory: imagesURL,
                    root: root, crypto: crypto, entries: &entries
                )
            }
            if let name = migrated.records[index].thumbnailFile {
                migrated.records[index].thumbnailFile = try migratePlaintextFile(
                    named: name, directoryName: "Thumbnails", directory: thumbnailsURL,
                    root: root, crypto: crypto, entries: &entries
                )
            }
        }
        migrated.schemaVersion = 3
        let marker = recoveryURL.appendingPathComponent("plaintext-cleanup.enc")
        try writePrivate(try crypto.seal(JSONEncoder.pasteRail.encode(PlaintextCleanupPlan(entries: entries))), to: marker)
        try persistSnapshot(
            migrated,
            indexURL: indexURL,
            backupURL: root.appendingPathComponent("history.backup.enc"),
            crypto: crypto,
            persistenceFailureInjector: persistenceFailureInjector,
            fileOperationInjector: fileOperationInjector
        )
        return migrated
    }

    private static func migratePlaintextFile(
        named name: String,
        directoryName: String,
        directory: URL,
        root: URL,
        crypto: CryptoStore,
        entries: inout [PlaintextCleanupEntry]
    ) throws -> String {
        guard !name.contains("/"), name != ".", name != ".." else { throw StoreError.encryptionUnavailable }
        let source = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: source.path) else { return name }
        let encryptedName = name + ".enc"
        try writePrivate(try crypto.seal(Data(contentsOf: source)), to: directory.appendingPathComponent(encryptedName))
        entries.append(.init(
            plaintextRelativePath: "\(directoryName)/\(name)",
            encryptedRelativePath: "\(directoryName)/\(encryptedName)"
        ))
        return encryptedName
    }

    private static func completePendingPlaintextCleanup(
        root: URL,
        payloadsURL: URL,
        imagesURL: URL,
        thumbnailsURL: URL,
        indexURL: URL,
        recoveryURL: URL,
        crypto: CryptoStore,
        fileOperationInjector: (@Sendable (ClipStoreFileOperation) throws -> Void)?
    ) throws {
        let marker = recoveryURL.appendingPathComponent("plaintext-cleanup.enc")
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let planData = try crypto.open(Data(contentsOf: marker))
        let plan = try JSONDecoder.pasteRail.decode(PlaintextCleanupPlan.self, from: planData)
        let snapshot = try decodeSnapshot(crypto: crypto, at: indexURL)
        let referenced = Set(
            snapshot.records.flatMap { [$0.payloadFile, $0.imageFile, $0.thumbnailFile].compactMap { $0 } }
        )
        let allowedRoots = ["Payloads": payloadsURL, "Images": imagesURL, "Thumbnails": thumbnailsURL]

        let validated = try plan.entries.compactMap {
            try validateCleanupEntry(
                $0, root: root, allowedRoots: allowedRoots, referenced: referenced, crypto: crypto
            )
        }
        try fileOperationInjector?(.afterCleanupValidation)
        for item in validated {
            let current = try validateCleanupEntry(
                item.entry, root: root, allowedRoots: allowedRoots, referenced: referenced, crypto: crypto
            )
            guard current?.identity == item.identity else { throw StoreError.encryptionUnavailable }
        }

        let quarantine = recoveryURL
            .appendingPathComponent("PlaintextQuarantine", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        var recoveryCopies: [(source: URL, encrypted: URL, identity: FileIdentity)] = []
        for item in validated {
            let destination = quarantine.appendingPathComponent("\(UUID().uuidString).enc")
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let plaintext = try Data(contentsOf: item.plaintext)
            try writePrivate(try crypto.seal(plaintext), to: destination)
            guard try crypto.open(Data(contentsOf: destination)) == plaintext else {
                throw StoreError.encryptionUnavailable
            }
            recoveryCopies.append((item.plaintext, destination, item.identity))
        }
        for copy in recoveryCopies {
            guard try fileIdentity(of: copy.source) == copy.identity,
                  !isSymbolicLink(copy.source),
                  try crypto.open(Data(contentsOf: copy.encrypted)) == Data(contentsOf: copy.source) else {
                throw StoreError.encryptionUnavailable
            }
        }
        for copy in recoveryCopies {
            try FileManager.default.removeItem(at: copy.source)
        }
        try FileManager.default.removeItem(at: marker)
    }

    private struct ValidatedCleanupEntry {
        let entry: PlaintextCleanupEntry
        let plaintext: URL
        let identity: FileIdentity
    }

    private struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private static func validateCleanupEntry(
        _ entry: PlaintextCleanupEntry,
        root: URL,
        allowedRoots: [String: URL],
        referenced: Set<String>,
        crypto: CryptoStore
    ) throws -> ValidatedCleanupEntry? {
        let plaintext = try validatedMigrationURL(
            relativePath: entry.plaintextRelativePath, root: root, allowedRoots: allowedRoots
        )
        let encrypted = try validatedMigrationURL(
            relativePath: entry.encryptedRelativePath, root: root, allowedRoots: allowedRoots
        )
        guard FileManager.default.fileExists(atPath: plaintext.path) else { return nil }
        guard FileManager.default.fileExists(atPath: encrypted.path),
              !isSymbolicLink(plaintext),
              !isSymbolicLink(encrypted) else {
            throw StoreError.encryptionUnavailable
        }
        _ = try crypto.open(Data(contentsOf: encrypted))
        if entry.encryptedRelativePath != "history.enc" {
            guard referenced.contains(encrypted.lastPathComponent) else {
                throw StoreError.encryptionUnavailable
            }
        }
        return ValidatedCleanupEntry(
            entry: entry,
            plaintext: plaintext,
            identity: try fileIdentity(of: plaintext)
        )
    }

    private static func fileIdentity(of url: URL) throws -> FileIdentity {
        var information = stat()
        guard lstat(url.path, &information) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard (information.st_mode & S_IFMT) != S_IFLNK else {
            throw StoreError.encryptionUnavailable
        }
        return FileIdentity(device: information.st_dev, inode: information.st_ino)
    }

    private static func validatedMigrationURL(
        relativePath: String,
        root: URL,
        allowedRoots: [String: URL]
    ) throws -> URL {
        guard !relativePath.hasPrefix("/"), !relativePath.split(separator: "/").contains("..") else {
            throw StoreError.encryptionUnavailable
        }
        if relativePath == "history.json" || relativePath == "history.enc" {
            return root.appendingPathComponent(relativePath).standardizedFileURL
        }
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let allowed = allowedRoots[String(parts[0])], !parts[1].isEmpty else {
            throw StoreError.encryptionUnavailable
        }
        let url = allowed.appendingPathComponent(String(parts[1])).standardizedFileURL
        let allowedPath = allowed.standardizedFileURL.path + "/"
        guard url.path.hasPrefix(allowedPath) else { throw StoreError.encryptionUnavailable }
        return url
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func preferredImageData(in payload: ClipPayload) -> Data? {
        let types = [
            NSPasteboard.PasteboardType.png.rawValue,
            NSPasteboard.PasteboardType.tiff.rawValue,
            "public.jpeg"
        ]
        return types.compactMap { type in
            payload.representations.first { $0.pasteboardType == type }?.data
        }.first
    }

    private func pngData(from image: NSImage, maximumDimension: CGFloat?) throws -> Data {
        let size: NSSize
        if let maximumDimension {
            let scale = min(1, maximumDimension / max(image.size.width, image.size.height))
            size = NSSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        } else {
            size = image.size
        }
        let output = NSImage(size: size)
        output.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        output.unlockFocus()
        guard let tiff = output.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw StoreError.invalidImage
        }
        return data
    }
}

private extension JSONEncoder {
    static var pasteRail: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var pasteRail: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
