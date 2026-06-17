import AppKit
import Foundation

@MainActor
final class PasteboardMonitor {
    static let maximumCaptureBytes = 20 * 1024 * 1024
    private let pasteboard: NSPasteboard
    private let policy: SecurityPolicy
    private let onCapture: @MainActor (ClipPayload, ClipKind, String, String, SourceApplication) -> Void
    private var timer: Timer?
    private var observerToken: NSObjectProtocol?
    private var lastChangeCount: Int
    private var sourceCandidate: SourceApplication?
    private(set) var isStarted = false
    var sourceCandidateForTesting: SourceApplication? { sourceCandidate }
    var internalWriteTrackingCountForTesting: Int { 0 }

    init(
        pasteboard: NSPasteboard = .general,
        policy: SecurityPolicy = SecurityPolicy(),
        initialSource: SourceApplication? = nil,
        usesSystemInitialSource: Bool = true,
        onCapture: @escaping @MainActor (ClipPayload, ClipKind, String, String, SourceApplication) -> Void
    ) {
        self.pasteboard = pasteboard
        self.policy = policy
        self.onCapture = onCapture
        lastChangeCount = pasteboard.changeCount
        sourceCandidate = initialSource ?? (usesSystemInitialSource ? NSWorkspace.shared.frontmostApplication.map(Self.sourceApplication) : nil)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        observerToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self?.handleActivation(Self.sourceApplication(app)) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer?.tolerance = 0.08
    }

    func stop() {
        guard isStarted else { return }
        timer?.invalidate()
        timer = nil
        if let observerToken {
            NSWorkspace.shared.notificationCenter.removeObserver(observerToken)
            self.observerToken = nil
        }
        isStarted = false
    }

    func markInternalWrite() {
        lastChangeCount = pasteboard.changeCount
    }

    func handleActivation(_ newApplication: SourceApplication) {
        if pasteboard.changeCount != lastChangeCount {
            processChange(source: sourceCandidate)
        }
        if newApplication.bundleIdentifier != Bundle.main.bundleIdentifier {
            sourceCandidate = newApplication
        }
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        processChange(source: sourceCandidate)
    }

    private func processChange(source: SourceApplication?) {
        let newCount = pasteboard.changeCount
        let changeDelta = newCount - lastChangeCount
        lastChangeCount = newCount
        guard changeDelta == 1 else { return }
        guard let source else { return }
        let typeNames = Self.allTypeNames(in: pasteboard)
        guard policy.decision(types: typeNames, sourceBundleIdentifier: source.bundleIdentifier) == .capture else { return }
        guard let captured = Self.capture(from: pasteboard) else { return }
        onCapture(captured.payload, captured.kind, captured.title, captured.searchText, source)
    }

    static func allTypeNames(in pasteboard: NSPasteboard) -> [String] {
        var names = Set(pasteboard.types?.map(\.rawValue) ?? [])
        for item in pasteboard.pasteboardItems ?? [] {
            names.formUnion(item.types.map(\.rawValue))
        }
        return Array(names)
    }

    private static func sourceApplication(_ app: NSRunningApplication) -> SourceApplication {
        SourceApplication(name: app.localizedName, bundleIdentifier: app.bundleIdentifier, processIdentifier: app.processIdentifier)
    }

    static func capture(from pasteboard: NSPasteboard) -> CapturedClip? {
        let allTypes = allTypeNames(in: pasteboard)
        guard !allTypes.contains(SecurityPolicy.concealedType),
              !allTypes.contains(SecurityPolicy.transientType) else { return nil }
        let allowed: [NSPasteboard.PasteboardType] = [
            .string, .rtf, .html, .URL, .fileURL, .png, .tiff,
            NSPasteboard.PasteboardType("public.jpeg")
        ]
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.filter(allowed.contains).compactMap { type -> ClipPayload.Representation? in
                guard let data = item.data(forType: type) else { return nil }
                return .init(pasteboardType: type.rawValue, data: data)
            }
        }.filter { !$0.isEmpty }
        guard !items.isEmpty else { return nil }
        let payload = ClipPayload(items: items)
        guard payload.representations.reduce(0, { $0 + $1.data.count }) <= maximumCaptureBytes else { return nil }
        if payload.representations.allSatisfy({ representation in
            guard representation.pasteboardType == NSPasteboard.PasteboardType.string.rawValue else { return false }
            return String(data: representation.data, encoding: .utf8)?.isEmpty ?? true
        }) { return nil }
        let representations = payload.representations
        let names = Set(representations.map(\.pasteboardType))
        let pngType = NSPasteboard.PasteboardType.png.rawValue
        let tiffType = NSPasteboard.PasteboardType.tiff.rawValue
        let jpegType = "public.jpeg"
        let kind: ClipKind
        if !names.isDisjoint(with: [pngType, tiffType, jpegType]) {
            kind = .image
        } else if names.contains(NSPasteboard.PasteboardType.fileURL.rawValue) {
            kind = .file
        } else if names.contains(NSPasteboard.PasteboardType.URL.rawValue) {
            kind = .url
        } else if names.contains(NSPasteboard.PasteboardType.rtf.rawValue) || names.contains(NSPasteboard.PasteboardType.html.rawValue) {
            kind = .richText
        } else {
            kind = .text
        }
        let plainText = payload.plainText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var searchText = plainText
        var title = plainText.isEmpty ? kind.label : String(plainText.prefix(180))
        if kind == .url, let data = representations.first(where: { $0.pasteboardType == NSPasteboard.PasteboardType.URL.rawValue })?.data {
            let urlText = String(data: data, encoding: .utf8) ?? URL(dataRepresentation: data, relativeTo: nil)?.absoluteString ?? ""
            if !urlText.isEmpty {
                title = String(urlText.prefix(180))
                searchText = [plainText, urlText].filter { !$0.isEmpty }.joined(separator: "\n")
            }
        } else if kind == .file {
            let paths = representations.compactMap { representation -> String? in
                guard representation.pasteboardType == NSPasteboard.PasteboardType.fileURL.rawValue else { return nil }
                return URL(dataRepresentation: representation.data, relativeTo: nil)?.path
            }
            if let first = paths.first { title = first }
            searchText = ([plainText] + paths).filter { !$0.isEmpty }.joined(separator: "\n")
        } else if kind == .image,
                  let imageRepresentation = representations.first(where: {
                      [pngType, tiffType, jpegType].contains($0.pasteboardType)
                  }),
                  let image = NSImage(data: imageRepresentation.data) {
            let format = imageRepresentation.pasteboardType == jpegType ? "JPEG"
                : imageRepresentation.pasteboardType == pngType ? "PNG" : "TIFF"
            title = "\(format) \(Int(image.size.width)) x \(Int(image.size.height))"
        }
        return CapturedClip(payload: payload, kind: kind, title: title, searchText: searchText)
    }
}
