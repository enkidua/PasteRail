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
            HSplitView {
                List(model.filteredRecords, selection: $model.selection) { record in
                    ClipRow(model: model, record: record)
                        .tag(record.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { model.paste(record, dismissPanel: dismiss) }
                }
                .listStyle(.inset)
                .frame(minWidth: 410)

                detail
                    .frame(minWidth: 260, idealWidth: 310)
            }
            Divider()
            queueBar
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(.regularMaterial)
        .onAppear { searchFocused = true }
        .onExitCommand(perform: dismiss)
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
        HStack(spacing: 12) {
            Image(systemName: "railway")
                .font(.title2)
            TextField("Search clipboard history", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
            Button("Queue") { model.addSelectionToQueue() }
                .disabled(model.selection.isEmpty)
            Button("Plain Queue") { model.addSelectionToQueue(plainText: true) }
                .disabled(model.selection.isEmpty)
        }
        .padding(12)
    }

    @ViewBuilder
    private var detail: some View {
        if let id = model.selection.first,
           let record = model.records.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 14) {
                Label(record.kind.label, systemImage: record.kind.symbol)
                    .font(.headline)
                if record.kind == .image {
                    AsyncImageView(model: model, record: record)
                } else {
                    ScrollView {
                        Text(record.isSensitive ? "Sensitive content" : record.title)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Spacer()
                Text(record.sourceAppName ?? "Unknown application")
                    .foregroundStyle(.secondary)
                Text(record.createdAt.formatted())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Paste") {
                        model.paste(record, dismissPanel: dismiss)
                    }
                    .keyboardShortcut(.return, modifiers: [])
                    Button("Paste Plain") {
                        model.paste(record, plainText: true, dismissPanel: dismiss)
                    }
                    .disabled(record.searchText.isEmpty)
                }
            }
            .padding(16)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "clipboard")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Select an item")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var queueBar: some View {
        HStack {
            Label(
                model.queue.isEmpty ? "Queue empty" : "Queue \(min(model.queueIndex + 1, model.queue.count)) of \(model.queue.count)",
                systemImage: "list.number"
            )
            Spacer()
            if let current = queueRecord(at: model.queueIndex) {
                Text("Current: \(current.title)")
                    .lineLimit(1)
            }
            if let next = queueRecord(at: model.queueIndex + 1) {
                Text("Next: \(next.title)")
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
        .padding(10)
    }

    private func queueRecord(at index: Int) -> ClipRecord? {
        guard model.queue.indices.contains(index) else { return nil }
        let id = model.queue[index].clipID
        return model.records.first { $0.id == id }
    }
}

private struct ClipRow: View {
    let model: AppModel
    let record: ClipRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: record.kind.symbol)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.isSensitive ? "Sensitive content" : record.title)
                    .lineLimit(2)
                HStack {
                    Text(record.sourceAppName ?? "Unknown")
                    Text(record.createdAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(record.isSensitive ? "\(record.kind.label), Sensitive content" : "\(record.kind.label), \(record.title)")
    }
}

private struct AsyncImageView: View {
    let model: AppModel
    let record: ClipRecord
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .task(id: record.id) {
            image = await model.thumbnail(for: record)
        }
    }
}
