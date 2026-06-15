import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var model: AppModel
    let dismiss: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            historyList
            Divider()
            queueBar
        }
        .frame(minWidth: 620, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { searchFocused = true }
        .onExitCommand(perform: dismiss)
        .onChange(of: model.filter) { _ in ensureVisibleFocus() }
        .onChange(of: model.searchText) { _ in ensureVisibleFocus() }
        .alert("PasteRail", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "railway")
                    .font(.title2)
                TextField("Search clipboard history", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                Button("Queue Selected") { model.addSelectionToQueue() }
                    .disabled(model.selection.isEmpty)
                Button("Plain Text Queue") { model.addSelectionToQueue(plainText: true) }
                    .disabled(model.selection.isEmpty)
            }
            Picker("History type", selection: $model.filter) {
                ForEach(ClipFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(12)
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if model.filteredRecords.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "clipboard")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No Clipboard History")
                                .font(.headline)
                            Text("Copy something or change the current search and filter.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        ForEach(model.filteredRecords) { record in
                            ClipRow(
                                model: model,
                                record: record,
                                isFocused: model.focusedRecordID == record.id,
                                isSelectedForQueue: model.selection.contains(record.id),
                                isQueued: model.isQueued(record)
                            )
                            .id(record.id)
                            .onTapGesture {
                                model.focus(record.id)
                                model.paste(record, dismissPanel: dismiss)
                            }
                            Divider()
                        }
                    }
                }
            }
            .onChange(of: model.focusedRecordID) { id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var queueBar: some View {
        HStack(spacing: 8) {
            Label(
                model.queue.isEmpty
                    ? "Queue empty"
                    : "\(min(model.queueIndex + 1, model.queue.count)) / \(model.queue.count)",
                systemImage: "list.number"
            )
            .frame(minWidth: 90, alignment: .leading)
            if let current = queueRecord(at: model.queueIndex) {
                Text("Current: \(current.isSensitive ? "Sensitive content" : current.title)")
                    .lineLimit(1)
            }
            if let next = queueRecord(at: model.queueIndex + 1) {
                Text("Next: \(next.isSensitive ? "Sensitive content" : next.title)")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Previous") { model.previousQueueItem() }
                .disabled(model.queueIndex == 0)
            Button("Restart") { model.restartQueue() }
                .disabled(model.queue.isEmpty)
            Button("Skip") { model.skipQueueItem() }
                .disabled(model.queueIndex >= model.queue.count)
            Button("Paste Next") { model.pasteNextQueueItem(dismissPanel: dismiss) }
                .disabled(model.queueIndex >= model.queue.count)
            Button("Clear") { model.clearQueue() }
                .disabled(model.queue.isEmpty)
        }
        .controlSize(.small)
        .padding(10)
    }

    private func queueRecord(at index: Int) -> ClipRecord? {
        guard model.queue.indices.contains(index) else { return nil }
        let id = model.queue[index].clipID
        return model.records.first { $0.id == id }
    }

    private func ensureVisibleFocus() {
        if !model.filteredRecords.contains(where: { $0.id == model.focusedRecordID }) {
            model.focusedRecordID = model.filteredRecords.first?.id
        }
    }
}

private struct ClipRow: View {
    let model: AppModel
    let record: ClipRecord
    let isFocused: Bool
    let isSelectedForQueue: Bool
    let isQueued: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.toggleQueueSelection(record.id)
            } label: {
                Image(systemName: isSelectedForQueue ? "checkmark.square.fill" : "square")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Select for queue")

            preview
                .frame(width: 58, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayTitle)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if record.isPinned {
                        Image(systemName: "pin.fill")
                            .accessibilityLabel("Pinned")
                    }
                    if isQueued {
                        Image(systemName: "text.line.first.and.arrowtriangle.forward")
                            .accessibilityLabel("In paste queue")
                    }
                }
                HStack(spacing: 8) {
                    Text(record.kind.label)
                    Text(record.sourceAppName ?? "Unknown application")
                    Text(record.createdAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(isFocused ? Color.accentColor.opacity(0.16) : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityTitle)
    }

    @ViewBuilder
    private var preview: some View {
        if record.kind == .image {
            ThumbnailView(model: model, record: record)
        } else {
            Image(systemName: record.kind.symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var displayTitle: String {
        if record.isSensitive { return "Sensitive content" }
        if record.kind == .file {
            return URL(fileURLWithPath: record.title).lastPathComponent
        }
        return record.title
    }

    private var accessibilityTitle: String {
        record.isSensitive
            ? "\(record.kind.label), Sensitive content"
            : "\(record.kind.label), \(displayTitle)"
    }
}

private struct ThumbnailView: View {
    let model: AppModel
    let record: ClipRecord
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else if failed {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Image preview unavailable")
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: record.id) {
            image = await model.thumbnail(for: record)
            failed = image == nil
        }
    }
}
