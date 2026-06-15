import AppKit
import SwiftUI

@MainActor
final class PanelController: NSWindowController, NSWindowDelegate {
    private let model: AppModel
    private let defaults: UserDefaults
    private var isProgrammaticMove = false

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "PasteRail"
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
        panel.delegate = self
        panel.contentViewController = NSHostingController(rootView: PanelView(model: model) {
            panel.orderOut(nil)
        })
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func toggle() {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
            return
        }
        model.rememberTargetApplication()
        restorePosition(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func dismissPanel() {
        window?.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticMove, let window, let screen = window.screen else { return }
        defaults.set(NSStringFromRect(window.frame), forKey: positionKey(for: screen))
    }

    private func restorePosition(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var frame = window.frame
        if let screen, let saved = defaults.string(forKey: positionKey(for: screen)) {
            frame = NSRectFromString(saved)
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        } else {
            frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2)
        }
        isProgrammaticMove = true
        window.setFrame(frame, display: false)
        isProgrammaticMove = false
    }

    private func positionKey(for screen: NSScreen) -> String {
        let frame = screen.frame
        return "PasteRail.Panel.\(screen.localizedName).\(Int(frame.origin.x)).\(Int(frame.origin.y)).\(Int(frame.width))x\(Int(frame.height))"
    }
}
