import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    private static let filterDefaultsKey = "PasteRail.HistoryFilter"

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
    let pasteEnvironment: SystemPasteEnvironment
    let pasteService: PasteService
    private let defaults: UserDefaults
    private(set) var monitor: PasteboardMonitor!

    init(store: ClipStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        filter = ClipFilter(
            rawValue: defaults.string(forKey: Self.filterDefaultsKey) ?? ""
        ) ?? .all
        pasteEnvironment = SystemPasteEnvironment()
        pasteService = PasteService(environment: pasteEnvironment)
        pasteEnvironment.didWritePasteboard = { [weak self] in self?.monitor.markInternalWrite() }
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
                } catch {
                    self.errorMessage = "PasteRail could not safely store this clipboard item."
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
            errorMessage = await store.recoveryMessage
            monitor.start()
        }
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
                if let message = pasteErrorMessage(result) { errorMessage = message }
            } catch {
                errorMessage = "PasteRail could not load this clipboard item."
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
                errorMessage = "The paste queue could not be saved."
            }
        }
    }

    func pasteNextQueueItem(target: PasteTarget? = nil, dismissPanel: @escaping () -> Void = {}) {
        Task {
            guard let entry = await store.currentQueueEntry(),
                  let record = await store.record(id: entry.clipID) else { return }
            do {
                let payload = try await store.loadPayload(for: record)
                let result = await pasteService.paste(
                    payload,
                    asPlainText: entry.plainText,
                    target: target ?? targetApplication,
                    dismissPanel: dismissPanel
                )
                if result == .eventSent {
                    try await store.advanceQueue()
                    await reload()
                } else if let message = pasteErrorMessage(result) {
                    errorMessage = message
                }
            } catch {
                errorMessage = "Paste was sent, but queue progress could not be saved. The queue position was preserved."
            }
        }
    }

    private func pasteErrorMessage(_ result: PasteResult) -> String? {
        switch result {
        case .eventSent:
            nil
        case .eventFailedPreviousRestored:
            "Paste shortcut delivery failed. The previous clipboard contents were restored."
        case .eventFailedPreviousLost:
            "Paste shortcut delivery failed, and PasteRail could not restore the previous clipboard contents."
        case .newWriteFailedPreviousRestored:
            "PasteRail could not write this item. The previous clipboard contents were restored."
        case .newWriteFailedPreviousLost:
            "PasteRail could not write this item or restore the previous clipboard contents."
        case let .preparationFailed(message):
            message
        }
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
                errorMessage = "The paste queue change could not be saved. The previous queue was kept."
                await reload()
            }
        }
    }

    func thumbnail(for record: ClipRecord) async -> NSImage? {
        await store.thumbnail(for: record)
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
