import AppKit
import Darwin
import XCTest
@testable import PasteRail

final class PasteRailTests: XCTestCase {
    private var root: URL!
    private var keyStore: MemoryKeyStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        keyStore = MemoryKeyStore()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSecurityRejectsProtectedTypesAndPasswordManagers() {
        let policy = SecurityPolicy()
        XCTAssertEqual(policy.decision(types: [SecurityPolicy.concealedType], sourceBundleIdentifier: "com.apple.TextEdit"), .reject("Protected pasteboard type"))
        XCTAssertEqual(policy.decision(types: ["public.utf8-plain-text"], sourceBundleIdentifier: "com.1password.1password"), .reject("Excluded source application"))
        XCTAssertEqual(policy.decision(types: ["public.utf8-plain-text"], sourceBundleIdentifier: "com.apple.TextEdit"), .capture)
    }

    func testTextCaptureAndRestartPersistence() async throws {
        let store = try ClipStore(rootURL: root, keyStore: keyStore)
        let payload = textPayload("hello")
        _ = try await store.capture(payload: payload, kind: .text, title: "hello", searchText: "hello", sourceAppName: "TextEdit", sourceBundleIdentifier: "com.apple.TextEdit")
        let reopened = try ClipStore(rootURL: root, keyStore: keyStore)
        let records = await reopened.records()
        XCTAssertEqual(records.count, 1)
        let loaded = try await reopened.loadPayload(for: records[0])
        XCTAssertEqual(loaded, payload)
    }

    func testUpdateReopensExistingEncryptedHistoryWithSameKeyWithoutReplacingData() async throws {
        let stableKeyStore = MemoryKeyStore()
        let previousBuildStore = try ClipStore(rootURL: root, keyStore: stableKeyStore)
        let payload = textPayload("update-compatible-record")
        let record = try await previousBuildStore.capture(
            payload: payload,
            kind: .text,
            title: "update-compatible-record",
            searchText: "update-compatible-record",
            sourceAppName: nil,
            sourceBundleIdentifier: "com.apple.TextEdit"
        )
        let encryptedIndexBeforeUpdate = try Data(contentsOf: root.appendingPathComponent("history.enc"))
        let encryptedPayloadBeforeUpdate = try Data(
            contentsOf: root.appendingPathComponent("Payloads/\(record.payloadFile)")
        )

        let updatedBuildStore = try ClipStore(rootURL: root, keyStore: stableKeyStore)
        let updatedRecords = await updatedBuildStore.records()
        let reopenedRecord = try XCTUnwrap(updatedRecords.first)
        let reopenedPayload = try await updatedBuildStore.loadPayload(for: reopenedRecord)
        XCTAssertEqual(reopenedPayload, payload)

        XCTAssertThrowsError(try ClipStore(rootURL: root, keyStore: MemoryKeyStore(byte: 0x33)))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("history.enc")), encryptedIndexBeforeUpdate)
        XCTAssertEqual(
            try Data(contentsOf: root.appendingPathComponent("Payloads/\(record.payloadFile)")),
            encryptedPayloadBeforeUpdate
        )
    }

    func testDuplicateMovesExistingRecordWithoutGrowingHistory() async throws {
        let store = try ClipStore(rootURL: root, keyStore: keyStore)
        let payload = textPayload("same")
        _ = try await store.capture(payload: payload, kind: .text, title: "same", searchText: "same", sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
        _ = try await store.capture(payload: payload, kind: .text, title: "same", searchText: "same", sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
        let count = await store.records().count
        XCTAssertEqual(count, 1)
    }

    func testFIFOQueueKeepsTwentyItemOrder() async throws {
        let store = try ClipStore(rootURL: root, keyStore: keyStore)
        var ids: [UUID] = []
        for index in 0..<20 {
            let text = "item \(index)"
            let record = try await store.capture(payload: textPayload(text), kind: .text, title: text, searchText: text, sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
            ids.append(record.id)
        }
        try await store.enqueue(ids)
        for id in ids {
            let currentID = await store.currentQueueEntry()?.clipID
            XCTAssertEqual(currentID, id)
            try await store.advanceQueue()
        }
        let finalEntry = await store.currentQueueEntry()
        XCTAssertNil(finalEntry)
    }

    func testCorruptIndexRestoresBackupAndPreservesCorruptFile() async throws {
        let store = try ClipStore(rootURL: root, keyStore: keyStore)
        _ = try await store.capture(payload: textPayload("one"), kind: .text, title: "one", searchText: "one", sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
        _ = try await store.capture(payload: textPayload("two"), kind: .text, title: "two", searchText: "two", sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
        try Data("not encrypted data".utf8).write(to: root.appendingPathComponent("history.enc"))
        let recovered = try ClipStore(rootURL: root, keyStore: keyStore)
        let recoveredRecords = await recovered.records()
        let recoveryMessage = await recovered.recoveryMessage
        XCTAssertFalse(recoveredRecords.isEmpty)
        XCTAssertNotNil(recoveryMessage)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Recovery").path).contains { $0.hasPrefix("history.corrupt-") })
    }

    func testBackupRecoveryPreservesPayloadOnlyReferencedByDamagedCurrentIndex() async throws {
        let store = try ClipStore(rootURL: root, keyStore: keyStore)
        _ = try await store.capture(payload: textPayload("backup"), kind: .text, title: "backup", searchText: "backup", sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
        let latest = try await store.capture(payload: textPayload("latest"), kind: .text, title: "latest", searchText: "latest", sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
        let latestPayload = root.appendingPathComponent("Payloads").appendingPathComponent(latest.payloadFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: latestPayload.path))

        try Data("damaged".utf8).write(to: root.appendingPathComponent("history.enc"))
        _ = try ClipStore(rootURL: root, keyStore: keyStore)

        XCTAssertTrue(FileManager.default.fileExists(atPath: latestPayload.path))
        let candidates = try Data(contentsOf: root.appendingPathComponent("Recovery/orphan-candidates.json"))
        XCTAssertTrue(String(decoding: candidates, as: UTF8.self).contains(latest.payloadFile))
    }

    func testBackupRecoveryRestoresWritableIndexAndPersistsCaptureAndQueue() async throws {
        let store = try ClipStore(rootURL: root, keyStore: keyStore)
        let first = try await store.capture(payload: textPayload("first"), kind: .text, title: "first", searchText: "first", sourceAppName: nil, sourceBundleIdentifier: nil)
        let second = try await store.capture(payload: textPayload("second"), kind: .text, title: "second", searchText: "second", sourceAppName: nil, sourceBundleIdentifier: nil)
        try await store.enqueue([first.id, second.id])
        try await store.restartQueue()
        try Data("damaged-current-index".utf8).write(to: root.appendingPathComponent("history.enc"))

        let recovered = try ClipStore(rootURL: root, keyStore: keyStore)
        let recoveredBeforeCapture = await recovered.records()
        XCTAssertFalse(recoveredBeforeCapture.isEmpty)
        let third = try await recovered.capture(payload: textPayload("third"), kind: .text, title: "third", searchText: "third", sourceAppName: nil, sourceBundleIdentifier: nil)
        try await recovered.advanceQueue()

        let reopened = try ClipStore(rootURL: root, keyStore: keyStore)
        let reopenedRecords = await reopened.records()
        let reopenedIDs = Set(reopenedRecords.map(\.id))
        let queueState = await reopened.queueState()
        XCTAssertTrue(reopenedIDs.contains(third.id))
        XCTAssertTrue(reopenedIDs.contains(first.id) || reopenedIDs.contains(second.id))
        XCTAssertEqual(queueState.1, 1)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Recovery").path)
            .contains { $0.hasPrefix("history.corrupt-") && $0.hasSuffix(".enc") })
    }

    func testInvalidImageLeavesNoPayloadOrImageOrphans() async throws {
        let store = try ClipStore(rootURL: root, keyStore: keyStore)
        let payload = ClipPayload(items: [[.init(pasteboardType: NSPasteboard.PasteboardType.png.rawValue, data: Data("bad image".utf8))]])
        do {
            _ = try await store.capture(payload: payload, kind: .image, title: "bad", searchText: "", sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
            XCTFail("Expected invalid image")
        } catch {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Payloads").path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Images").path), [])
    }

    func testIndexWriteFailureRollsBackNewPayload() async throws {
        let failure = PersistenceFailure()
        let store = try ClipStore(rootURL: root, keyStore: keyStore, persistenceFailureInjector: { try failure.check() })
        failure.enabled = true
        do {
            _ = try await store.capture(payload: textPayload("cannot persist"), kind: .text, title: "cannot persist", searchText: "cannot persist", sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
            XCTFail("Expected index write failure")
        } catch {}
        let payloads = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Payloads").path)
        let records = await store.records()
        XCTAssertTrue(payloads.isEmpty)
        XCTAssertTrue(records.isEmpty)
    }

    func testQueuePersistenceFailuresRollbackMemoryAndRemainUsable() async throws {
        let failure = PersistenceFailure()
        let store = try ClipStore(rootURL: root, keyStore: keyStore, persistenceFailureInjector: { try failure.check() })
        let first = try await store.capture(payload: textPayload("first"), kind: .text, title: "first", searchText: "first", sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
        let second = try await store.capture(payload: textPayload("second"), kind: .text, title: "second", searchText: "second", sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
        try await store.enqueue([first.id, second.id])

        failure.enabled = true
        await XCTAssertThrowsAsyncError { try await store.advanceQueue() }
        let afterAdvanceFailure = await store.currentQueueEntry()?.clipID
        XCTAssertEqual(afterAdvanceFailure, first.id)

        await XCTAssertThrowsAsyncError { try await store.clearQueue() }
        let afterClearFailure = await store.currentQueueEntry()?.clipID
        let countAfterClearFailure = await store.queueState().0.count
        XCTAssertEqual(afterClearFailure, first.id)
        XCTAssertEqual(countAfterClearFailure, 2)

        await XCTAssertThrowsAsyncError { try await store.enqueue([second.id]) }
        let countAfterEnqueueFailure = await store.queueState().0.count
        XCTAssertEqual(countAfterEnqueueFailure, 2)

        failure.enabled = false
        try await store.advanceQueue()
        let afterRecovery = await store.currentQueueEntry()?.clipID
        XCTAssertEqual(afterRecovery, second.id)
    }

    @MainActor
    func testMultiplePasteboardItemsArePreserved() {
        let board = NSPasteboard.withUniqueName()
        let first = NSPasteboardItem()
        first.setString("first", forType: .string)
        let second = NSPasteboardItem()
        second.setString("second", forType: .string)
        board.writeObjects([first, second])
        let captured = PasteboardMonitor.capture(from: board)
        XCTAssertEqual(captured?.payload.items.count, 2)
        XCTAssertEqual(captured?.payload.items[0].first?.data, Data("first".utf8))
    }

    func testDigestIncludesPasteboardItemBoundaries() async throws {
        let store = try ClipStore(rootURL: root, keyStore: keyStore)
        let a = ClipPayload(items: [
            [.init(pasteboardType: NSPasteboard.PasteboardType.string.rawValue, data: Data("a".utf8))],
            [.init(pasteboardType: NSPasteboard.PasteboardType.string.rawValue, data: Data("b".utf8))]
        ])
        let b = ClipPayload(items: [[
            .init(pasteboardType: NSPasteboard.PasteboardType.string.rawValue, data: Data("a".utf8)),
            .init(pasteboardType: NSPasteboard.PasteboardType.string.rawValue, data: Data("b".utf8))
        ]])
        _ = try await store.capture(payload: a, kind: .text, title: "a", searchText: "a", sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
        _ = try await store.capture(payload: b, kind: .text, title: "b", searchText: "b", sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
        let count = await store.records().count
        XCTAssertEqual(count, 2)
    }

    func testPlaintextStoreMigratesToEncryptedVersionThree() async throws {
        let payloadDirectory = root.appendingPathComponent("Payloads")
        try FileManager.default.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)
        let payloadName = "legacy.json"
        let payloadEncoder = JSONEncoder()
        payloadEncoder.dateEncodingStrategy = .iso8601
        try payloadEncoder.encode(textPayload("legacy")).write(to: payloadDirectory.appendingPathComponent(payloadName))
        let record = ClipRecord(
            id: UUID(), kind: .text, title: "legacy", searchText: "legacy", createdAt: Date(),
            sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit", payloadFile: payloadName,
            imageFile: nil, thumbnailFile: nil, digest: nil, isSensitive: false, isPinned: false
        )
        let legacy = ClipStore.Snapshot(schemaVersion: 2, records: [record], queue: [], queueIndex: 0)
        let indexURL = root.appendingPathComponent("history.json")
        try payloadEncoder.encode(legacy).write(to: indexURL, options: .atomic)

        let migrated = try ClipStore(rootURL: root, keyStore: keyStore)
        let migratedRecords = await migrated.records()
        XCTAssertNotNil(migratedRecords.first?.digest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("history.enc").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: indexURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadDirectory.appendingPathComponent(payloadName).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: payloadDirectory.appendingPathComponent(payloadName + ".enc").path))
    }

    @MainActor
    func testURLAndRTFSearchMetadata() {
        let urlBoard = NSPasteboard.withUniqueName()
        urlBoard.setString("https://example.invalid/path", forType: .URL)
        XCTAssertTrue(PasteboardMonitor.capture(from: urlBoard)?.searchText.contains("example.invalid") == true)

        let rtfBoard = NSPasteboard.withUniqueName()
        let item = NSPasteboardItem()
        item.setData(Data("{\\rtf1 hello}".utf8), forType: .rtf)
        item.setString("hello", forType: .string)
        rtfBoard.writeObjects([item])
        XCTAssertEqual(PasteboardMonitor.capture(from: rtfBoard)?.searchText, "hello")
    }

    @MainActor
    func testPNGJPEGAndTIFFCapture() throws {
        let image = NSImage(size: NSSize(width: 8, height: 6))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 6).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let formats: [(NSPasteboard.PasteboardType, Data)] = [
            (.png, try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))),
            (.init("public.jpeg"), try XCTUnwrap(bitmap.representation(using: .jpeg, properties: [:]))),
            (.tiff, tiff)
        ]
        for (type, data) in formats {
            let board = NSPasteboard.withUniqueName()
            let item = NSPasteboardItem()
            item.setData(data, forType: type)
            board.writeObjects([item])
            let captured = try XCTUnwrap(PasteboardMonitor.capture(from: board))
            XCTAssertEqual(captured.kind, .image)
            XCTAssertTrue(captured.title.contains("8 x 6"))
        }
    }

    @MainActor
    func testFileURLCapture() throws {
        let board = NSPasteboard.withUniqueName()
        let item = NSPasteboardItem()
        let url = URL(fileURLWithPath: "/tmp/PasteRail-test.txt")
        item.setData(url.dataRepresentation, forType: .fileURL)
        board.writeObjects([item])
        let captured = try XCTUnwrap(PasteboardMonitor.capture(from: board))
        XCTAssertEqual(captured.kind, .file)
        XCTAssertTrue(captured.searchText.contains("PasteRail-test.txt"))
    }

    @MainActor
    func testAccessibilityFailureDoesNotChangeClipboard() async {
        let environment = FakePasteEnvironment()
        environment.trusted = false
        let service = PasteService(environment: environment, ownBundleIdentifier: "io.pasterail.PasteRail")
        let result = await service.paste(textPayload("secret"), asPlainText: false, target: environment.frontmostTarget, dismissPanel: {})
        XCTAssertNotEqual(result, .eventSent)
        XCTAssertEqual(environment.writeCount, 0)
    }

    @MainActor
    func testTargetApplicationIsRestoredBeforeWrite() async {
        let environment = FakePasteEnvironment()
        let service = PasteService(environment: environment, ownBundleIdentifier: "io.pasterail.PasteRail")
        let result = await service.paste(textPayload("hello"), asPlainText: false, target: environment.frontmostTarget, dismissPanel: { environment.actions.append("dismiss") })
        XCTAssertEqual(result, .eventSent)
        XCTAssertEqual(environment.actions, ["dismiss", "activate", "wait", "write", "send", "discard"])
    }

    @MainActor
    func testPasteFailureCanKeepQueuePosition() async throws {
        let store = try ClipStore(rootURL: root, keyStore: keyStore)
        let record = try await store.capture(payload: textPayload("queued"), kind: .text, title: "queued", searchText: "queued", sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
        try await store.enqueue([record.id])
        let environment = FakePasteEnvironment()
        environment.sendSucceeds = false
        let service = PasteService(environment: environment, ownBundleIdentifier: "io.pasterail.PasteRail")
        let result = await service.paste(textPayload("queued"), asPlainText: false, target: environment.frontmostTarget, dismissPanel: {})
        if result == .eventSent { try await store.advanceQueue() }
        let queueIndex = await store.queueState().1
        XCTAssertEqual(queueIndex, 0)
    }

    @MainActor
    func testInternalClipboardWriteIsIgnoredOnce() {
        let board = NSPasteboard.withUniqueName()
        let monitor = PasteboardMonitor(pasteboard: board) { _, _, _, _, _ in }
        board.setString("internal", forType: .string)
        monitor.markInternalWrite()
        XCTAssertTrue(monitor.shouldIgnoreChange(count: board.changeCount))
        XCTAssertFalse(monitor.shouldIgnoreChange(count: board.changeCount))
    }

    @MainActor
    func testFailedPasteboardWriteRestoresPreviousItems() {
        let old = [[ClipPayload.Representation(pasteboardType: NSPasteboard.PasteboardType.string.rawValue, data: Data("old".utf8))]]
        let access = FakePasteboardAccess(items: old)
        access.failNextReplace = true
        let environment = SystemPasteEnvironment(pasteboardAccess: access)
        var internalWrites = 0
        environment.didWritePasteboard = { internalWrites += 1 }

        XCTAssertEqual(environment.write(textPayload("new"), plainText: false), .newWriteFailedPreviousRestored)
        XCTAssertEqual(access.items, old)
        XCTAssertEqual(access.replaceCount, 2)
        XCTAssertEqual(internalWrites, 1)
    }

    @MainActor
    func testFailedPasteboardWriteAndRestoreReportsClipboardLoss() async {
        let old = [[ClipPayload.Representation(pasteboardType: NSPasteboard.PasteboardType.string.rawValue, data: Data("old".utf8))]]
        let access = FakePasteboardAccess(items: old)
        access.remainingFailures = 2
        let system = SystemPasteEnvironment(pasteboardAccess: access)
        let environment = DelegatingPasteEnvironment(system: system)
        let service = PasteService(environment: environment, ownBundleIdentifier: "io.pasterail.PasteRail")
        let result = await service.paste(textPayload("new"), asPlainText: false, target: environment.frontmostTarget, dismissPanel: {})
        XCTAssertEqual(result, .newWriteFailedPreviousLost)
    }

    @MainActor
    func testEventFailureRestoresPreviousClipboard() async {
        let environment = FakePasteEnvironment()
        environment.sendSucceeds = false
        environment.restoreSucceeds = true
        let service = PasteService(environment: environment, ownBundleIdentifier: "io.pasterail.PasteRail")
        let result = await service.paste(textPayload("new"), asPlainText: false, target: environment.frontmostTarget, dismissPanel: {})
        XCTAssertEqual(result, .eventFailedPreviousRestored)
        XCTAssertEqual(environment.actions.suffix(2), ["send", "restore"])
    }

    @MainActor
    func testEventFailureAndRestoreFailureAreDistinct() async {
        let environment = FakePasteEnvironment()
        environment.sendSucceeds = false
        environment.restoreSucceeds = false
        let service = PasteService(environment: environment, ownBundleIdentifier: "io.pasterail.PasteRail")
        let result = await service.paste(textPayload("new"), asPlainText: false, target: environment.frontmostTarget, dismissPanel: {})
        XCTAssertEqual(result, .eventFailedPreviousLost)
    }

    @MainActor
    func testSuccessfulPasteDiscardsPreviousClipboardSnapshot() async {
        let old = [[ClipPayload.Representation(
            pasteboardType: NSPasteboard.PasteboardType.string.rawValue,
            data: Data("old".utf8)
        )]]
        let access = FakePasteboardAccess(items: old)
        let system = SystemPasteEnvironment(pasteboardAccess: access)
        let environment = DelegatingPasteEnvironment(system: system)
        let service = PasteService(environment: environment, ownBundleIdentifier: "io.pasterail.PasteRail")

        let result = await service.paste(
            textPayload("new"),
            asPlainText: false,
            target: environment.frontmostTarget,
            dismissPanel: {}
        )
        XCTAssertEqual(result, .eventSent)
        XCTAssertFalse(system.hasPreviousClipboardSnapshot)
    }

    @MainActor
    func testSecondPasteFailureNeverRestoresFirstPasteSnapshot() async {
        let original = [[ClipPayload.Representation(
            pasteboardType: NSPasteboard.PasteboardType.string.rawValue,
            data: Data("original".utf8)
        )]]
        let between = [[ClipPayload.Representation(
            pasteboardType: NSPasteboard.PasteboardType.string.rawValue,
            data: Data("between".utf8)
        )]]
        let access = FakePasteboardAccess(items: original)
        let system = SystemPasteEnvironment(pasteboardAccess: access)
        let environment = DelegatingPasteEnvironment(system: system)
        let service = PasteService(environment: environment, ownBundleIdentifier: "io.pasterail.PasteRail")

        let firstResult = await service.paste(
            textPayload("first"),
            asPlainText: false,
            target: environment.frontmostTarget,
            dismissPanel: {}
        )
        XCTAssertEqual(firstResult, .eventSent)
        access.items = between
        environment.sendSucceeds = false
        let secondResult = await service.paste(
            textPayload("second"),
            asPlainText: false,
            target: environment.frontmostTarget,
            dismissPanel: {}
        )
        XCTAssertEqual(secondResult, .eventFailedPreviousRestored)
        XCTAssertEqual(access.items, between)
        XCTAssertFalse(system.hasPreviousClipboardSnapshot)
    }

    func testBackupCopyFailureKeepsExistingBackup() async throws {
        let store = try ClipStore(rootURL: root, keyStore: keyStore)
        _ = try await store.capture(payload: textPayload("one"), kind: .text, title: "one", searchText: "one", sourceAppName: nil, sourceBundleIdentifier: nil)
        _ = try await store.capture(payload: textPayload("two"), kind: .text, title: "two", searchText: "two", sourceAppName: nil, sourceBundleIdentifier: nil)
        let backup = root.appendingPathComponent("history.backup.enc")
        let originalBackup = try Data(contentsOf: backup)
        let failure = FileOperationFailure(.beforeBackupCopy)
        let failingStore = try ClipStore(rootURL: root, keyStore: keyStore, fileOperationInjector: { try failure.check($0) })

        await XCTAssertThrowsAsyncError {
            _ = try await failingStore.capture(payload: self.textPayload("three"), kind: .text, title: "three", searchText: "three", sourceAppName: nil, sourceBundleIdentifier: nil)
        }
        XCTAssertEqual(try Data(contentsOf: backup), originalBackup)
    }

    func testBackupReplaceFailureKeepsExistingBackup() async throws {
        let store = try ClipStore(rootURL: root, keyStore: keyStore)
        _ = try await store.capture(payload: textPayload("one"), kind: .text, title: "one", searchText: "one", sourceAppName: nil, sourceBundleIdentifier: nil)
        _ = try await store.capture(payload: textPayload("two"), kind: .text, title: "two", searchText: "two", sourceAppName: nil, sourceBundleIdentifier: nil)
        let backup = root.appendingPathComponent("history.backup.enc")
        let originalBackup = try Data(contentsOf: backup)
        let failure = FileOperationFailure(.beforeBackupReplace)
        let failingStore = try ClipStore(rootURL: root, keyStore: keyStore, fileOperationInjector: { try failure.check($0) })

        await XCTAssertThrowsAsyncError {
            _ = try await failingStore.capture(payload: self.textPayload("three"), kind: .text, title: "three", searchText: "three", sourceAppName: nil, sourceBundleIdentifier: nil)
        }
        XCTAssertEqual(try Data(contentsOf: backup), originalBackup)
    }

    func testIndexWriteFailureLeavesDecryptableIndexOrBackup() async throws {
        let store = try ClipStore(rootURL: root, keyStore: keyStore)
        _ = try await store.capture(payload: textPayload("one"), kind: .text, title: "one", searchText: "one", sourceAppName: nil, sourceBundleIdentifier: nil)
        let failure = FileOperationFailure(.beforeIndexWrite)
        let failingStore = try ClipStore(rootURL: root, keyStore: keyStore, fileOperationInjector: { try failure.check($0) })
        await XCTAssertThrowsAsyncError {
            _ = try await failingStore.capture(payload: self.textPayload("two"), kind: .text, title: "two", searchText: "two", sourceAppName: nil, sourceBundleIdentifier: nil)
        }

        let crypto = try CryptoStore(keyStore: keyStore)
        let candidates = ["history.enc", "history.backup.enc"].compactMap {
            try? crypto.open(Data(contentsOf: root.appendingPathComponent($0)))
        }
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.contains { (try? JSONDecoder.pasteRailTest.decode(ClipStore.Snapshot.self, from: $0)) != nil })
    }

    func testCleanupRejectsSymlinkReplacementAfterValidation() async throws {
        let source = try prepareLegacyStore(payloadNames: ["legacy.json"])[0]
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("outside".utf8).write(to: outside)
        let mutation = CleanupMutation {
            try FileManager.default.removeItem(at: source)
            try FileManager.default.createSymbolicLink(at: source, withDestinationURL: outside)
        }
        let reopened = try ClipStore(rootURL: root, keyStore: keyStore, fileOperationInjector: { try mutation.run(on: $0) })
        let warning = await reopened.recoveryMessage
        XCTAssertNotNil(warning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        try? FileManager.default.removeItem(at: outside)
    }

    func testCleanupRejectsInodeReplacementAfterValidation() async throws {
        let source = try prepareLegacyStore(payloadNames: ["legacy.json"])[0]
        let mutation = CleanupMutation {
            try FileManager.default.removeItem(at: source)
            try Data("replacement".utf8).write(to: source)
        }
        let reopened = try ClipStore(rootURL: root, keyStore: keyStore, fileOperationInjector: { try mutation.run(on: $0) })
        let warning = await reopened.recoveryMessage
        XCTAssertNotNil(warning)
        XCTAssertEqual(try Data(contentsOf: source), Data("replacement".utf8))
    }

    func testCleanupValidationFailureMovesNoEntries() throws {
        let sources = try prepareLegacyStore(payloadNames: ["first.json", "second.json"])
        let mutation = CleanupMutation {
            try FileManager.default.removeItem(at: sources[1])
            try Data("changed".utf8).write(to: sources[1])
        }
        _ = try ClipStore(rootURL: root, keyStore: keyStore, fileOperationInjector: { try mutation.run(on: $0) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: sources[0].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sources[1].path))
    }

    func testNormalMigrationQuarantinesEveryPlaintextEntry() throws {
        let sources = try prepareLegacyStore(payloadNames: ["first.json", "second.json"])
        _ = try ClipStore(rootURL: root, keyStore: keyStore)

        XCTAssertTrue(sources.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Payloads/first.json.enc").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Payloads/second.json.enc").path))
        let quarantine = root.appendingPathComponent("Recovery/PlaintextQuarantine")
        let quarantined = try FileManager.default.subpathsOfDirectory(atPath: quarantine.path)
        XCTAssertEqual(quarantined.filter { $0.hasSuffix(".enc") }.count, 3)
        XCTAssertFalse(quarantined.contains { $0.contains("first.json") || $0.contains("second.json") || $0.contains("history.json") })
    }

    func testMigrationLeavesNoPlaintextTextOrImageBytesAnywhereInStore() throws {
        let uniqueText = "PASTERAIL-MIGRATION-SECRET-\(UUID().uuidString)"
        let uniqueImageBytes = Data("PASTERAIL-IMAGE-BYTES-\(UUID().uuidString)".utf8)
        let payloadDirectory = root.appendingPathComponent("Payloads")
        let imageDirectory = root.appendingPathComponent("Images")
        try FileManager.default.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        let payloadName = "legacy-payload.json"
        let imageName = "legacy-image.bin"
        try JSONEncoder.pasteRailTest.encode(textPayload(uniqueText))
            .write(to: payloadDirectory.appendingPathComponent(payloadName))
        try uniqueImageBytes.write(to: imageDirectory.appendingPathComponent(imageName))
        let record = ClipRecord(
            id: UUID(), kind: .image, title: uniqueText, searchText: uniqueText,
            createdAt: Date(), sourceAppName: nil, sourceBundleIdentifier: nil,
            payloadFile: payloadName, imageFile: imageName, thumbnailFile: nil,
            digest: nil, isSensitive: false, isPinned: false
        )
        try JSONEncoder.pasteRailTest.encode(
            ClipStore.Snapshot(schemaVersion: 2, records: [record], queue: [], queueIndex: 0)
        ).write(to: root.appendingPathComponent("history.json"))

        _ = try ClipStore(rootURL: root, keyStore: keyStore)

        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])?
            .compactMap { $0 as? URL } ?? []
        for file in files {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let data = try Data(contentsOf: file)
            XCTAssertNil(data.range(of: Data(uniqueText.utf8)), "Plaintext text remained in \(file.path)")
            XCTAssertNil(data.range(of: uniqueImageBytes), "Plaintext image bytes remained in \(file.path)")
        }
    }

    func testOneThousandRecordsPersist() async throws {
        let store = try ClipStore(rootURL: root, keyStore: keyStore)
        for index in 0..<1_000 {
            let text = "record \(index)"
            _ = try await store.capture(payload: textPayload(text), kind: .text, title: text, searchText: text, sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
        }
        let records = await store.records()
        XCTAssertEqual(records.count, 1_000)
        let searchStarted = CFAbsoluteTimeGetCurrent()
        let matches = records.filter { $0.searchText.localizedCaseInsensitiveContains("999") }
        let searchDuration = CFAbsoluteTimeGetCurrent() - searchStarted
        XCTAssertEqual(matches.count, 1)
        XCTAssertLessThan(searchDuration, 0.05)
        let reopened = try ClipStore(rootURL: root, keyStore: keyStore)
        _ = try await reopened.capture(payload: textPayload("new item"), kind: .text, title: "new item", searchText: "new item", sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
        _ = try await reopened.capture(payload: textPayload("new item"), kind: .text, title: "new item", searchText: "new item", sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
        let metrics = await reopened.performanceMetrics
        print("PasteRail metrics: load=\(metrics.loadDuration)s save=\(metrics.lastSaveDuration ?? -1)s duplicate=\(metrics.lastDuplicateDuration ?? -1)s index=\(metrics.indexBytes) bytes resident=\(residentMemoryBytes()) bytes")
        XCTAssertLessThan(metrics.loadDuration, 0.5)
        XCTAssertLessThan(try XCTUnwrap(metrics.lastSaveDuration), 0.1)
        XCTAssertLessThan(try XCTUnwrap(metrics.lastDuplicateDuration), 0.02)
    }

    @MainActor
    func testPasswordManagerCopyIsAttributedBeforeTextEditActivation() {
        let board = NSPasteboard.withUniqueName()
        let passwordManager = SourceApplication(name: "Password", bundleIdentifier: "com.1password.1password", processIdentifier: 10)
        let textEdit = SourceApplication(name: "TextEdit", bundleIdentifier: "com.apple.TextEdit", processIdentifier: 11)
        var captures = 0
        let monitor = PasteboardMonitor(pasteboard: board, initialSource: passwordManager, usesSystemInitialSource: false) { _, _, _, _, _ in captures += 1 }
        board.setString("secret", forType: .string)
        monitor.handleActivation(textEdit)
        XCTAssertEqual(captures, 0)
    }

    @MainActor
    func testChangeImmediatelyAfterActivationUsesNewApplication() {
        let board = NSPasteboard.withUniqueName()
        let previous = SourceApplication(name: "Old", bundleIdentifier: "com.apple.Terminal", processIdentifier: 10)
        let current = SourceApplication(name: "TextEdit", bundleIdentifier: "com.apple.TextEdit", processIdentifier: 11)
        var source: SourceApplication?
        let monitor = PasteboardMonitor(pasteboard: board, initialSource: previous, usesSystemInitialSource: false) { _, _, _, _, app in source = app }
        monitor.handleActivation(current)
        let item = NSPasteboardItem()
        item.setString("new", forType: .string)
        board.writeObjects([item])
        monitor.handleActivation(current)
        XCTAssertEqual(source, current)
    }

    @MainActor
    func testUnknownSourceFailsClosed() {
        let board = NSPasteboard.withUniqueName()
        var captures = 0
        let monitor = PasteboardMonitor(pasteboard: board, usesSystemInitialSource: false) { _, _, _, _, _ in captures += 1 }
        board.setString("unknown", forType: .string)
        monitor.handleActivation(SourceApplication(name: "PasteRail", bundleIdentifier: Bundle.main.bundleIdentifier, processIdentifier: 1))
        XCTAssertEqual(captures, 0)
    }

    @MainActor
    func testProtectedTypeOnSecondItemRejectsWholePasteboard() {
        let board = NSPasteboard.withUniqueName()
        let first = NSPasteboardItem()
        first.setString("visible", forType: .string)
        let second = NSPasteboardItem()
        second.setData(Data(), forType: .init(SecurityPolicy.concealedType))
        board.writeObjects([first, second])
        XCTAssertTrue(PasteboardMonitor.allTypeNames(in: board).contains(SecurityPolicy.concealedType))
        XCTAssertEqual(
            SecurityPolicy().decision(types: PasteboardMonitor.allTypeNames(in: board), sourceBundleIdentifier: "com.apple.TextEdit"),
            .reject("Protected pasteboard type")
        )
        XCTAssertNil(PasteboardMonitor.capture(from: board))
    }

    @MainActor
    func testMultipleChangesAcrossActivationBoundaryFailClosed() {
        let board = NSPasteboard.withUniqueName()
        let previous = SourceApplication(name: "Old", bundleIdentifier: "com.apple.Terminal", processIdentifier: 10)
        let current = SourceApplication(name: "New", bundleIdentifier: "com.apple.TextEdit", processIdentifier: 11)
        var captures = 0
        let monitor = PasteboardMonitor(pasteboard: board, initialSource: previous, usesSystemInitialSource: false) { _, _, _, _, _ in captures += 1 }
        board.setString("one", forType: .string)
        board.setString("two", forType: .string)
        monitor.handleActivation(current)
        XCTAssertEqual(captures, 0)
    }

    @MainActor
    func testMonitorStartStopIsIdempotent() {
        let monitor = PasteboardMonitor(pasteboard: .withUniqueName()) { _, _, _, _, _ in }
        monitor.start()
        monitor.start()
        XCTAssertTrue(monitor.isStarted)
        monitor.stop()
        monitor.stop()
        XCTAssertFalse(monitor.isStarted)
    }

    func testKeyStoreFailureDoesNotCreateStorage() {
        XCTAssertThrowsError(try ClipStore(rootURL: root, keyStore: FailingKeyStore()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("history.enc").path))
    }

    func testCorruptCiphertextIsPreserved() throws {
        let keyStore = MemoryKeyStore()
        _ = try ClipStore(rootURL: root, keyStore: keyStore)
        try Data("corrupt ciphertext".utf8).write(to: root.appendingPathComponent("history.enc"))
        XCTAssertThrowsError(try ClipStore(rootURL: root, keyStore: keyStore))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Recovery").path).contains { $0.hasPrefix("history.corrupt-") })
    }

    func testEncryptedFilesDoNotContainPlaintext() async throws {
        let keyStore = MemoryKeyStore()
        let store = try ClipStore(rootURL: root, keyStore: keyStore)
        let secret = "UNIQUE-PASTERAIL-PLAINTEXT"
        let record = try await store.capture(payload: textPayload(secret), kind: .text, title: secret, searchText: secret, sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
        let index = try Data(contentsOf: root.appendingPathComponent("history.enc"))
        let payload = try Data(contentsOf: root.appendingPathComponent("Payloads/\(record.payloadFile)"))
        XCTAssertFalse(String(decoding: index, as: UTF8.self).contains(secret))
        XCTAssertFalse(String(decoding: payload, as: UTF8.self).contains(secret))
    }

    func testCleanupPlanRejectsAbsoluteAndParentPaths() async throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("outside".utf8).write(to: outside)
        let store = try ClipStore(rootURL: root, keyStore: keyStore)
        _ = try await store.capture(payload: textPayload("safe"), kind: .text, title: "safe", searchText: "safe", sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")

        try writeCleanupPlan(plaintext: outside.path, encrypted: "history.enc")
        let absoluteRetry = try ClipStore(rootURL: root, keyStore: keyStore)
        let absoluteWarning = await absoluteRetry.recoveryMessage
        let absoluteRecords = await absoluteRetry.records()
        XCTAssertNotNil(absoluteWarning)
        XCTAssertEqual(absoluteRecords.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))

        try writeCleanupPlan(plaintext: "../outside", encrypted: "history.enc")
        let parentRetry = try ClipStore(rootURL: root, keyStore: keyStore)
        let parentWarning = await parentRetry.recoveryMessage
        XCTAssertNotNil(parentWarning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        try? FileManager.default.removeItem(at: outside)
    }

    func testCleanupPlanRejectsSymlinkAndTampering() async throws {
        let store = try ClipStore(rootURL: root, keyStore: keyStore)
        _ = try await store.capture(payload: textPayload("safe"), kind: .text, title: "safe", searchText: "safe", sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("outside".utf8).write(to: outside)
        let link = root.appendingPathComponent("Payloads/link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        try writeCleanupPlan(plaintext: "Payloads/link", encrypted: "history.enc")
        let symlinkRetry = try ClipStore(rootURL: root, keyStore: keyStore)
        let symlinkWarning = await symlinkRetry.recoveryMessage
        XCTAssertNotNil(symlinkWarning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))

        try Data("tampered".utf8).write(to: root.appendingPathComponent("Recovery/plaintext-cleanup.enc"))
        let tamperedRetry = try ClipStore(rootURL: root, keyStore: keyStore)
        let tamperedWarning = await tamperedRetry.recoveryMessage
        XCTAssertNotNil(tamperedWarning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        try? FileManager.default.removeItem(at: outside)
    }

    func testCleanupPreservesPlaintextWhenEncryptedTargetFailsAuthentication() async throws {
        let store = try ClipStore(rootURL: root, keyStore: keyStore)
        let record = try await store.capture(payload: textPayload("safe"), kind: .text, title: "safe", searchText: "safe", sourceAppName: nil, sourceBundleIdentifier: "com.apple.TextEdit")
        let plaintext = root.appendingPathComponent("Payloads/plaintext.json")
        try Data("must remain".utf8).write(to: plaintext)
        let encrypted = root.appendingPathComponent("Payloads/\(record.payloadFile)")
        try Data("invalid ciphertext".utf8).write(to: encrypted)
        try writeCleanupPlan(plaintext: "Payloads/plaintext.json", encrypted: "Payloads/\(record.payloadFile)")

        let retry = try ClipStore(rootURL: root, keyStore: keyStore)
        let warning = await retry.recoveryMessage
        XCTAssertNotNil(warning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plaintext.path))
    }

    private func writeCleanupPlan(plaintext: String, encrypted: String) throws {
        let plan = ["entries": [[
            "plaintextRelativePath": plaintext,
            "encryptedRelativePath": encrypted
        ]]]
        let data = try JSONSerialization.data(withJSONObject: plan)
        let crypto = try CryptoStore(keyStore: keyStore)
        let marker = root.appendingPathComponent("Recovery/plaintext-cleanup.enc")
        try crypto.seal(data).write(to: marker, options: .atomic)
    }

    private func prepareLegacyStore(payloadNames: [String]) throws -> [URL] {
        let directory = root.appendingPathComponent("Payloads")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let records = try payloadNames.enumerated().map { index, name -> ClipRecord in
            try JSONEncoder.pasteRailTest.encode(textPayload("legacy \(index)"))
                .write(to: directory.appendingPathComponent(name))
            return ClipRecord(
                id: UUID(), kind: .text, title: "legacy \(index)", searchText: "legacy \(index)",
                createdAt: Date(), sourceAppName: nil, sourceBundleIdentifier: nil,
                payloadFile: name, imageFile: nil, thumbnailFile: nil, digest: nil,
                isSensitive: false, isPinned: false
            )
        }
        let snapshot = ClipStore.Snapshot(schemaVersion: 2, records: records, queue: [], queueIndex: 0)
        try JSONEncoder.pasteRailTest.encode(snapshot).write(to: root.appendingPathComponent("history.json"))
        return payloadNames.map { directory.appendingPathComponent($0) }
    }

    private func textPayload(_ text: String) -> ClipPayload {
        ClipPayload(items: [[.init(pasteboardType: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))]])
    }
}

private enum InjectedFailure: Error { case requested }

private final class MemoryKeyStore: EncryptionKeyStore, @unchecked Sendable {
    private let key: Data
    init(byte: UInt8 = 0x5A) {
        key = Data(repeating: byte, count: 32)
    }
    func loadOrCreateKey() throws -> Data { key }
}

private struct FailingKeyStore: EncryptionKeyStore {
    func loadOrCreateKey() throws -> Data { throw InjectedFailure.requested }
}

private final class PersistenceFailure: @unchecked Sendable {
    var enabled = false
    func check() throws {
        if enabled { throw InjectedFailure.requested }
    }
}

private final class FileOperationFailure: @unchecked Sendable {
    let operation: ClipStoreFileOperation
    init(_ operation: ClipStoreFileOperation) { self.operation = operation }
    func check(_ current: ClipStoreFileOperation) throws {
        if current == operation { throw InjectedFailure.requested }
    }
}

private final class CleanupMutation: @unchecked Sendable {
    private var hasRun = false
    private let mutation: () throws -> Void
    init(_ mutation: @escaping () throws -> Void) { self.mutation = mutation }
    func run(on operation: ClipStoreFileOperation) throws {
        guard operation == .afterCleanupValidation, !hasRun else { return }
        hasRun = true
        try mutation()
    }
}

private extension JSONEncoder {
    static var pasteRailTest: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var pasteRailTest: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension XCTestCase {
    func XCTAssertThrowsAsyncError(
        _ expression: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected error", file: file, line: line)
        } catch {}
    }
}

@MainActor
private final class FakePasteboardAccess: PasteboardAccess {
    var items: [[ClipPayload.Representation]]
    var failNextReplace = false
    var remainingFailures = 0
    var replaceCount = 0

    init(items: [[ClipPayload.Representation]]) {
        self.items = items
    }

    func snapshot() -> [[ClipPayload.Representation]] { items }

    func replace(with items: [[ClipPayload.Representation]]) -> Bool {
        replaceCount += 1
        if failNextReplace || remainingFailures > 0 {
            failNextReplace = false
            remainingFailures = max(0, remainingFailures - 1)
            return false
        }
        self.items = items
        return true
    }
}

@MainActor
private final class DelegatingPasteEnvironment: PasteEnvironment {
    let system: SystemPasteEnvironment
    var frontmostTarget: PasteTarget? = PasteTarget(processIdentifier: 42, bundleIdentifier: "com.apple.TextEdit")
    var sendSucceeds = true
    init(system: SystemPasteEnvironment) { self.system = system }
    func isRunning(_ target: PasteTarget) -> Bool { true }
    func activate(_ target: PasteTarget) -> Bool { true }
    func waitUntilFrontmost(_ target: PasteTarget, timeout: TimeInterval) async -> Bool { true }
    func accessibilityIsTrusted(prompt: Bool) -> Bool { true }
    func write(_ payload: ClipPayload, plainText: Bool) -> PasteboardWriteResult { system.write(payload, plainText: plainText) }
    func sendPasteShortcut() -> Bool { sendSucceeds }
    func restorePreviousClipboard() -> Bool { system.restorePreviousClipboard() }
    func discardPreviousClipboardSnapshot() { system.discardPreviousClipboardSnapshot() }
}

private func residentMemoryBytes() -> UInt64 {
    var info = mach_task_basic_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
}

@MainActor
private final class FakePasteEnvironment: PasteEnvironment {
    var frontmostTarget: PasteTarget? = PasteTarget(processIdentifier: 42, bundleIdentifier: "com.apple.TextEdit")
    var trusted = true
    var running = true
    var activationSucceeds = true
    var waitSucceeds = true
    var writeSucceeds = true
    var sendSucceeds = true
    var restoreSucceeds = true
    var writeCount = 0
    var actions: [String] = []

    func isRunning(_ target: PasteTarget) -> Bool { running }
    func activate(_ target: PasteTarget) -> Bool { actions.append("activate"); return activationSucceeds }
    func waitUntilFrontmost(_ target: PasteTarget, timeout: TimeInterval) async -> Bool { actions.append("wait"); return waitSucceeds }
    func accessibilityIsTrusted(prompt: Bool) -> Bool { trusted }
    func write(_ payload: ClipPayload, plainText: Bool) -> PasteboardWriteResult {
        actions.append("write")
        writeCount += 1
        return writeSucceeds ? .success : .newWriteFailedPreviousRestored
    }
    func sendPasteShortcut() -> Bool { actions.append("send"); return sendSucceeds }
    func restorePreviousClipboard() -> Bool { actions.append("restore"); return restoreSucceeds }
    func discardPreviousClipboardSnapshot() { actions.append("discard") }
}
