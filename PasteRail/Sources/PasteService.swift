import AppKit
import ApplicationServices
import Foundation

struct PasteTarget: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
}

enum PasteResult: Equatable {
    case eventSent
    case eventFailedPreviousRestored
    case eventFailedPreviousLost
    case newWriteFailedPreviousRestored
    case newWriteFailedPreviousLost
    case preparationFailed(String)
}

enum PasteboardWriteResult: Equatable {
    case success
    case newWriteFailedPreviousRestored
    case newWriteFailedPreviousLost
}

@MainActor
protocol PasteEnvironment {
    var frontmostTarget: PasteTarget? { get }
    func isRunning(_ target: PasteTarget) -> Bool
    func activate(_ target: PasteTarget) -> Bool
    func waitUntilFrontmost(_ target: PasteTarget, timeout: TimeInterval) async -> Bool
    func accessibilityIsTrusted(prompt: Bool) -> Bool
    func write(_ payload: ClipPayload, plainText: Bool) -> PasteboardWriteResult
    func restorePreviousClipboard() -> Bool
    func discardPreviousClipboardSnapshot()
    func sendPasteShortcut() -> Bool
}

@MainActor
final class SystemPasteEnvironment: PasteEnvironment {
    private let pasteboard: PasteboardAccess
    private var previousItems: [[ClipPayload.Representation]]?
    var didWritePasteboard: (() -> Void)?
    var hasPreviousClipboardSnapshot: Bool { previousItems != nil }

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = NativePasteboardAccess(pasteboard: pasteboard)
    }

    init(pasteboardAccess: PasteboardAccess) {
        pasteboard = pasteboardAccess
    }

    var frontmostTarget: PasteTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return PasteTarget(processIdentifier: app.processIdentifier, bundleIdentifier: app.bundleIdentifier)
    }

    func isRunning(_ target: PasteTarget) -> Bool {
        NSRunningApplication(processIdentifier: target.processIdentifier)?.isTerminated == false
    }

    func activate(_ target: PasteTarget) -> Bool {
        NSRunningApplication(processIdentifier: target.processIdentifier)?
            .activate(options: [.activateIgnoringOtherApps]) == true
    }

    func waitUntilFrontmost(_ target: PasteTarget, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
                return true
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
    }

    func accessibilityIsTrusted(prompt: Bool) -> Bool {
        if AXIsProcessTrusted() { return true }
        guard prompt else { return false }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func write(_ payload: ClipPayload, plainText: Bool) -> PasteboardWriteResult {
        discardPreviousClipboardSnapshot()
        let items: [[ClipPayload.Representation]]
        if plainText {
            guard let text = payload.plainText else { return .newWriteFailedPreviousRestored }
            items = [[.init(pasteboardType: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))]]
        } else {
            items = payload.items.filter { !$0.isEmpty }
        }
        guard !items.isEmpty else { return .newWriteFailedPreviousRestored }
        let previousItems = pasteboard.snapshot()
        self.previousItems = previousItems
        guard pasteboard.replace(with: items) else {
            let restored = pasteboard.replace(with: previousItems)
            self.previousItems = nil
            didWritePasteboard?()
            return restored ? .newWriteFailedPreviousRestored : .newWriteFailedPreviousLost
        }
        didWritePasteboard?()
        return .success
    }

    func restorePreviousClipboard() -> Bool {
        guard let previousItems else {
            discardPreviousClipboardSnapshot()
            return false
        }
        let restored = pasteboard.replace(with: previousItems)
        discardPreviousClipboardSnapshot()
        didWritePasteboard?()
        return restored
    }

    func discardPreviousClipboardSnapshot() {
        previousItems = nil
    }

    func sendPasteShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

@MainActor
protocol PasteboardAccess {
    func snapshot() -> [[ClipPayload.Representation]]
    func replace(with items: [[ClipPayload.Representation]]) -> Bool
}

@MainActor
final class NativePasteboardAccess: PasteboardAccess {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    func snapshot() -> [[ClipPayload.Representation]] {
        var items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map {
                    ClipPayload.Representation(pasteboardType: type.rawValue, data: $0)
                }
            }
        }
        let representedTypes = Set(items.flatMap { $0.map(\.pasteboardType) })
        let rootOnly = (pasteboard.types ?? []).compactMap { type -> ClipPayload.Representation? in
            guard !representedTypes.contains(type.rawValue), let data = pasteboard.data(forType: type) else { return nil }
            return .init(pasteboardType: type.rawValue, data: data)
        }
        if !rootOnly.isEmpty { items.append(rootOnly) }
        return items
    }

    func replace(with items: [[ClipPayload.Representation]]) -> Bool {
        let objects = items.compactMap { representations -> NSPasteboardItem? in
            guard !representations.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for representation in representations {
                item.setData(representation.data, forType: .init(representation.pasteboardType))
            }
            return item
        }
        guard !objects.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects(objects)
    }
}

@MainActor
final class PasteService {
    private let environment: PasteEnvironment
    private let ownBundleIdentifier: String?

    init(environment: PasteEnvironment, ownBundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        self.environment = environment
        self.ownBundleIdentifier = ownBundleIdentifier
    }

    func currentTarget() -> PasteTarget? {
        validTarget(environment.frontmostTarget)
    }

    func paste(
        _ payload: ClipPayload,
        asPlainText: Bool,
        target: PasteTarget?,
        dismissPanel: () -> Void
    ) async -> PasteResult {
        guard payloadIsWritable(payload, plainText: asPlainText) else {
            return .preparationFailed("This item has no writable representation.")
        }
        guard environment.accessibilityIsTrusted(prompt: true) else {
            return .preparationFailed("Enable PasteRail in System Settings > Privacy & Security > Accessibility.")
        }
        guard let target = validTarget(target), environment.isRunning(target) else {
            return .preparationFailed("The previous application is no longer available.")
        }
        dismissPanel()
        guard environment.activate(target),
              await environment.waitUntilFrontmost(target, timeout: 0.6) else {
            return .preparationFailed("PasteRail could not restore the target application.")
        }
        switch environment.write(payload, plainText: asPlainText) {
        case .success:
            break
        case .newWriteFailedPreviousRestored:
            return .newWriteFailedPreviousRestored
        case .newWriteFailedPreviousLost:
            return .newWriteFailedPreviousLost
        }
        guard environment.sendPasteShortcut() else {
            return environment.restorePreviousClipboard()
                ? .eventFailedPreviousRestored
                : .eventFailedPreviousLost
        }
        environment.discardPreviousClipboardSnapshot()
        return .eventSent
    }

    private func validTarget(_ target: PasteTarget?) -> PasteTarget? {
        guard let target,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              target.bundleIdentifier != ownBundleIdentifier else { return nil }
        return target
    }

    private func payloadIsWritable(_ payload: ClipPayload, plainText: Bool) -> Bool {
        plainText ? payload.plainText != nil : payload.items.contains { !$0.isEmpty }
    }
}
