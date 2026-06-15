import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var records: [ClipRecord] = []
    @Published private(set) var queue: [QueueEntry] = []
    @Published private(set) var queueIndex = 0
    @Published var searchText = ""
    @Published var selection: Set<UUID> = []
    @Published var errorMessage: String?
    @Published private(set) var targetApplication: PasteTarget?

    let store: ClipStore
    let pasteEnvironment: SystemPasteEnvironment
    let pasteService: PasteService
    private(set) var monitor: PasteboardMonitor!

    init(store: ClipStore) {
        self.store = store
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
        guard !query.isEmpty else { return records }
        return records.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.searchText.localizedCaseInsensitiveContains(query)
                || ($0.sourceAppName?.localizedCaseInsensitiveContains(query) ?? false)
        }
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
