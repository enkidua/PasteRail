import AppKit
import Carbon
import SwiftUI

@main
struct PasteRailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            VStack(alignment: .leading, spacing: 12) {
                Text("PasteRail")
                    .font(.title2.bold())
                Text("Clipboard history stays on this Mac. PasteRail contains no network client, analytics, ads, or update service.")
                    .frame(width: 420, alignment: .leading)
            }
            .padding(24)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var model: AppModel!
    private var panelController: PanelController!
    private var panelHotKey: HotKey!
    private var queueHotKey: HotKey!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do {
            model = AppModel(store: try ClipStore())
        } catch {
            let alert = NSAlert()
            alert.messageText = "PasteRail could not open its private local storage."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        panelController = PanelController(model: model)
        configureStatusItem()
        panelHotKey = HotKey(keyCode: 9, modifiers: UInt32(cmdKey | shiftKey), id: 1) { [weak self] in
            self?.panelController.toggle()
        }
        queueHotKey = HotKey(keyCode: 35, modifiers: UInt32(cmdKey | optionKey), id: 2) { [weak self] in
            guard let self else { return }
            let target = self.pasteServiceTarget()
            self.model.pasteNextQueueItem(target: target)
        }
        model.start()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "railway", accessibilityDescription: "PasteRail")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open PasteRail", action: #selector(openPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Paste Next Queue Item", action: #selector(pasteNext), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PasteRail", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func openPanel() {
        panelController.toggle()
    }

    @objc private func pasteNext() {
        model.pasteNextQueueItem(target: pasteServiceTarget())
    }

    private func pasteServiceTarget() -> PasteTarget? {
        model.pasteService.currentTarget()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
