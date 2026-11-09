import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    private static let filterDefaultsKey = "PasteRail.HistoryFilter"
    private static let maximumCachedThumbnails = 30

    @Published private(set) var records: [ClipRecord] = []
    @Published private(set) var queue: [QueueEntry] = []
    @Published private(set) var queueIndex = 0
    @Published var searchText = ""
    @Published var selection: Set<UUID> = []
    @Published var focusedRecordID: UUID?
    @Published var filter: ClipFilter {
        didSet { defaults.set(filter.rawValue, forKey: Self.filterDefaultsKey) }
    }
    @Published var errorMessage: String?
    @Published private(set) var targetApplication: PasteTarget?

    let store: ClipStore
    let pasteService: PasteService
    private let defaults: UserDefaults
    private let languageManager: AppLanguageManager
    private var queuePasteTask: Task<Void, Never>?
    private var thumbnailCache: [UUID: NSImage] = [:]
    private var thumbnailCacheOrder: [UUID] = []
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private(set) var monitor: PasteboardMonitor!

    init(
        store: ClipStore,
        defaults: UserDefaults = .standard,
        pasteEnvironment: PasteEnvironment? = nil,
        languageManager: AppLanguageManager = .shared
    ) {
        self.store = store
        self.defaults = defaults
        self.languageManager = languageManager
        filter = ClipFilter(
            rawValue: defaults.string(forKey: Self.filterDefaultsKey) ?? ""
        ) ?? .all
        if let pasteEnvironment {
            pasteService = PasteService(environment: pasteEnvironment)
        } else {
            let systemEnvironment = SystemPasteEnvironment()
            pasteService = PasteService(environment: systemEnvironment)
            systemEnvironment.didWritePasteboard = { [weak self] in self?.monitor.markInternalWrite() }
        }
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        memoryPressureSource?.setEventHandler { [weak self] in
            Task { @MainActor in self?.clearThumbnailCache() }
        }
        memoryPressureSource?.resume()
        monitor = PasteboardMonitor { [weak self] payload, kind, title, searchText, app in
            guard let self else { return }
            Task {
                do {
                    _ = try await store.capture(
                        payload: payload,
                        kind: kind,
                        title: title,
                        searchText: searchText,
                        sourceAppName: app.name,
                        sourceBundleIdentifier: app.bundleIdentifier
                    )
                    await self.reload()
                } catch ClipStore.StoreError.historyLimitReached {
                    self.showError(.captureHistoryLimit)
                } catch ClipStore.StoreError.storageLimitReached {
                    self.showError(.captureStorageLimit)
                } catch {
                    self.showError(.captureFailed)
                }
            }
        }
    }

    var filteredRecords: [ClipRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return records.filter { record in
            guard filter.includes(record.kind) else { return false }
            guard !query.isEmpty else { return true }
            return record.title.localizedCaseInsensitiveContains(query)
                || record.searchText.localizedCaseInsensitiveContains(query)
                || (record.sourceAppName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var focusedRecord: ClipRecord? {
        guard let focusedRecordID else { return filteredRecords.first }
        return filteredRecords.first { $0.id == focusedRecordID }
    }

    func start() {
        Task {
            await reload()
            let notices = await store.recoveryNotices
            if !notices.isEmpty {
                errorMessage = notices.map { languageManager.message(for: $0) }.joined(separator: "\n")
            }
            monitor.start()
        }
    }

    func stop() {
        monitor.stop()
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
    }

    func rememberTargetApplication() {
        if let target = pasteService.currentTarget() {
            targetApplication = target
        }
    }

    func reload() async {
        records = await store.records()
        let state = await store.queueState()
        queue = state.0
        queueIndex = state.1
        normalizeFocusedRecord()
    }

    func moveFocus(_ movement: FocusMovement) {
        let visible = filteredRecords
        guard !visible.isEmpty else {
            focusedRecordID = nil
            return
        }
        let currentIndex = focusedRecordID.flatMap { id in visible.firstIndex { $0.id == id } } ?? 0
        let target: Int
        switch movement {
        case .previous:
            target = max(0, currentIndex - 1)
        case .next:
            target = min(visible.count - 1, currentIndex + 1)
        case .pageUp:
            target = max(0, currentIndex - 10)
        case .pageDown:
            target = min(visible.count - 1, currentIndex + 10)
        case .first:
            target = 0
        case .last:
            target = visible.count - 1
        }
        focusedRecordID = visible[target].id
    }

    func pasteFocused(plainText: Bool, dismissPanel: @escaping () -> Void) {
        guard let record = focusedRecord else { return }
        paste(record, plainText: plainText, dismissPanel: dismissPanel)
    }

    func isQueued(_ record: ClipRecord) -> Bool {
        queue.contains { $0.clipID == record.id }
    }

    func toggleQueueSelection(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
        focusedRecordID = id
    }

    func togglePinned(_ record: ClipRecord) {
        Task {
            do {
                try await store.setPinned(record.id, pinned: !record.isPinned)
                await reload()
            } catch {
                showError(.pinChangeFailed)
                await reload()
            }
        }
    }

    func focus(_ id: UUID) {
        focusedRecordID = id
    }

    private func normalizeFocusedRecord() {
        if let focusedRecordID, filteredRecords.contains(where: { $0.id == focusedRecordID }) {
            return
        }
        focusedRecordID = filteredRecords.first?.id
    }

    func paste(_ record: ClipRecord, plainText: Bool = false, dismissPanel: @escaping () -> Void) {
        Task {
            do {
                let payload = try await store.loadPayload(for: record)
                let result = await pasteService.paste(
                    payload,
                    asPlainText: plainText,
                    target: targetApplication,
                    dismissPanel: dismissPanel
                )
                showPasteResult(result)
            } catch {
                showError(.clipboardItemLoadFailed)
            }
        }
    }

    func addSelectionToQueue(plainText: Bool = false) {
        let ordered = filteredRecords.filter { selection.contains($0.id) }.map(\.id)
        Task {
            do {
                try await store.enqueue(ordered, plainText: plainText)
                await reload()
            } catch {
                showError(.queueSaveFailed)
            }
        }
    }

    /// Queue pastes run one at a time, so pressing the shortcut twice quickly pastes
    /// two consecutive entries instead of the same entry twice.
    @discardableResult
    func pasteNextQueueItem(target: PasteTarget? = nil, dismissPanel: @escaping () -> Void = {}) -> Task<Void, Never> {
        let previous = queuePasteTask
        let task = Task {
            await previous?.value
            await performQueuePaste(target: target, dismissPanel: dismissPanel)
        }
        queuePasteTask = task
        return task
    }

    private func performQueuePaste(target: PasteTarget?, dismissPanel: @escaping () -> Void) async {
        guard let entry = await store.currentQueueEntry(),
              let record = await store.record(id: entry.clipID) else { return }
        let payload: ClipPayload
        do {
            payload = try await store.loadPayload(for: record)
        } catch {
            showError(.queueItemLoadFailed)
            return
        }
        let result = await pasteService.paste(
            payload,
            asPlainText: entry.plainText,
            target: target ?? targetApplication,
            dismissPanel: dismissPanel
        )
        guard result == .eventSent else {
            showPasteResult(result)
            return
        }
        do {
            try await store.advanceQueue()
        } catch {
            showError(.queueAdvanceFailed)
        }
        await reload()
    }

    private func showError(_ key: AppLanguageManager.TextKey) {
        errorMessage = languageManager.text(key)
    }

    private func showPasteResult(_ result: PasteResult) {
        if let message = languageManager.message(for: result) { errorMessage = message }
    }

    func previousQueueItem() {
        performQueueMutation { try await self.store.previousQueueEntry() }
    }

    func restartQueue() {
        performQueueMutation { try await self.store.restartQueue() }
    }

    func skipQueueItem() {
        performQueueMutation { try await self.store.skipQueueEntry() }
    }

    func clearQueue() {
        performQueueMutation { try await self.store.clearQueue() }
    }

    private func performQueueMutation(_ operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await operation()
                await reload()
            } catch {
                showError(.queueChangeFailed)
                await reload()
            }
        }
    }

    func thumbnail(for record: ClipRecord) async -> NSImage? {
        if let cached = thumbnailCache[record.id] {
            rememberThumbnailUse(record.id)
            return cached
        }
        guard let data = await store.thumbnailData(for: record),
              let image = NSImage(data: data) else {
            return nil
        }
        thumbnailCache[record.id] = image
        rememberThumbnailUse(record.id)
        trimThumbnailCache()
        return image
    }

    private func rememberThumbnailUse(_ id: UUID) {
        thumbnailCacheOrder.removeAll { $0 == id }
        thumbnailCacheOrder.insert(id, at: 0)
    }

    private func trimThumbnailCache() {
        while thumbnailCacheOrder.count > Self.maximumCachedThumbnails {
            let id = thumbnailCacheOrder.removeLast()
            thumbnailCache.removeValue(forKey: id)
        }
    }

    private func clearThumbnailCache() {
        thumbnailCache.removeAll()
        thumbnailCacheOrder.removeAll()
    }
}

enum FocusMovement {
    case previous
    case next
    case pageUp
    case pageDown
    case first
    case last
}
