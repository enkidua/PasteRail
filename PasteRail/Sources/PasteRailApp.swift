import AppKit
import Carbon
import Darwin
import SwiftUI

@main
struct PasteRailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

private struct SettingsView: View {
    @ObservedObject private var languageManager = AppLanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PasteRail")
                .font(.title2.bold())
            Text(languageManager.text(.settingsPrivacy))
                .frame(width: 420, alignment: .leading)
        }
        .padding(24)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let hideWelcomeDefaultsKey = "PasteRail.HideWelcome"
    private static let openPanelHotKeyID: UInt32 = 1
    private static let queueHotKeyID: UInt32 = 2
    private var statusItem: NSStatusItem!
    private var model: AppModel?
    private var panelController: PanelController?
    private var panelHotKey: HotKey?
    private var queueHotKey: HotKey?
    private let languageManager = AppLanguageManager.shared
    private let accessibilityManager = AccessibilityPermissionManager()
    private var openShortcutState = OpenShortcutState(shortcut: PasteRailShortcut.current, status: nil)
    private var queueShortcutStatus: HotKeyRegistrationResult?

    private var openShortcut: PasteRailShortcut { openShortcutState.shortcut }

    private var hotKeyWarnings: [String] {
        HotKeyWarnings.messages(
            open: openShortcutState,
            queueStatus: queueShortcutStatus,
            language: languageManager.language
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("PasteRail launched")
        print("App path: \(Bundle.main.bundlePath)")
        print("Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        print("KeyStore type: \(PasteRailKeyStoreMode.current.rawValue)")
        print("Selected language: \(languageManager.language.rawValue)")
        print("Accessibility trusted: \(accessibilityManager.isTrusted())")
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        startPasteRail()
        showWelcomeIfNeeded()
    }

    private func startPasteRail() {
        do {
            model = AppModel(store: try ClipStore())
            print("Store loaded success")
        } catch {
            print("Store loaded failure: \(error)")
            showStorageError()
            return
        }
        guard let model else { return }
        panelController = PanelController(model: model)
        registerOpenShortcut(openShortcut, allowRollback: false)
        registerQueueShortcut()
        model.start()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.toolTip = "PasteRail"
            if let image = NSImage(systemSymbolName: "railway", accessibilityDescription: "PasteRail") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "PR"
            }
        }
        rebuildMenu()
        print("Status item created")
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: languageManager.text(.openPasteRail), action: #selector(openPanel), keyEquivalent: "")
        menu.addItem(withTitle: languageManager.text(.showWelcome), action: #selector(showWelcomeFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: languageManager.text(.pasteNextQueueItem), action: #selector(pasteNext), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: languageManager.text(.openAccessibilitySettings), action: #selector(openAccessibilitySettings), keyEquivalent: "")
        menu.addItem(withTitle: languageManager.text(.requestAccessibilityPermission), action: #selector(requestAccessibilityPermission), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(languageMenuItem())
        menu.addItem(shortcutMenuItem())
        menu.addItem(withTitle: languageManager.text(.copyDiagnostics), action: #selector(copyDiagnostics), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: languageManager.text(.resetData), action: #selector(resetData), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: languageManager.text(.quit), action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func languageMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: languageManager.text(.language), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for language in AppLanguage.allCases {
            let child = NSMenuItem(title: language.displayName, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            child.representedObject = language.rawValue
            child.state = languageManager.language == language ? .on : .off
            child.target = self
            submenu.addItem(child)
        }
        item.submenu = submenu
        return item
    }

    private func shortcutMenuItem() -> NSMenuItem {
        let status = HotKeyRegistrationResult.localizedStatus(
            openShortcutState.status,
            language: languageManager.language,
            shortcutLabel: openShortcut.label
        )
        let item = NSMenuItem(
            title: "\(languageManager.text(.shortcut)) (\(openShortcut.label), \(status))",
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu()
        for shortcut in PasteRailShortcut.allCases {
            let child = NSMenuItem(title: shortcut.label, action: #selector(selectShortcut(_:)), keyEquivalent: "")
            child.representedObject = shortcut.rawValue
            child.state = openShortcut == shortcut ? .on : .off
            child.target = self
            submenu.addItem(child)
        }
        item.submenu = submenu
        return item
    }

    @objc private func openPanel() {
        panelController?.toggle()
    }

    @objc private func pasteNext() {
        model?.pasteNextQueueItem(target: pasteServiceTarget())
    }

    private func pasteServiceTarget() -> PasteTarget? {
        model?.pasteService.currentTarget()
    }

    @objc private func showWelcomeFromMenu() {
        showWelcome(force: true)
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let language = AppLanguage(rawValue: raw) else { return }
        languageManager.language = language
        rebuildMenu()
        showWelcome(force: true)
    }

    @objc private func selectShortcut(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let shortcut = PasteRailShortcut(rawValue: raw) else { return }
        guard ShortcutSelectionDecision.shouldRegister(
            current: openShortcut,
            requested: shortcut,
            currentStatus: openShortcutState.status
        ) else {
            rebuildMenu()
            return
        }
        let rejected = registerOpenShortcut(shortcut, allowRollback: true)
        rebuildMenu()
        if let rejected {
            showHotKeyWarningAlert(messages: [
                rejected.localizedMessage(language: languageManager.language, shortcutLabel: shortcut.label)
            ])
        }
    }

    private func showWelcomeIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.hideWelcomeDefaultsKey) else {
            let warnings = hotKeyWarnings
            if !warnings.isEmpty { showHotKeyWarningAlert(messages: warnings) }
            return
        }
        showWelcome(force: false)
    }

    private func showWelcome(force: Bool) {
        let alert = NSAlert()
        alert.messageText = languageManager.text(.welcomeTitle)
        alert.informativeText = WelcomeContent.lines(
            languageManager: languageManager,
            openShortcut: openShortcutState,
            queueStatus: queueShortcutStatus,
            isDeveloperIDSigned: DistributionSignature.isDeveloperIDSigned
        ).joined(separator: "\n")
        alert.addButton(withTitle: languageManager.text(.openClipboardPanel))
        alert.addButton(withTitle: languageManager.text(.quit))
        alert.addButton(withTitle: languageManager.text(.ok))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = languageManager.text(.dontShowAgain)
        AppActivation.activatePasteRail()
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: Self.hideWelcomeDefaultsKey)
        } else if force {
            UserDefaults.standard.set(false, forKey: Self.hideWelcomeDefaultsKey)
        }
        switch response {
        case .alertFirstButtonReturn:
            openPanel()
        case .alertSecondButtonReturn:
            quit()
        default:
            break
        }
    }

    private func showHotKeyWarningAlert(messages: [String]) {
        let alert = NSAlert()
        alert.messageText = languageManager.text(.hotKeyWarningTitle)
        alert.informativeText = messages.joined(separator: "\n")
        alert.addButton(withTitle: languageManager.text(.ok))
        AppActivation.activatePasteRail()
        alert.runModal()
    }

    @objc private func openAccessibilitySettings() {
        accessibilityManager.openAccessibilitySettings()
    }

    @objc private func requestAccessibilityPermission() {
        accessibilityManager.requestThenOpenSettings()
    }

    @objc private func copyDiagnostics() {
        let diagnostics = diagnosticsText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
        model?.monitor.markInternalWrite()
        let alert = NSAlert()
        alert.messageText = languageManager.text(.diagnosticsCopied)
        alert.addButton(withTitle: languageManager.text(.ok))
        alert.runModal()
    }

    @objc private func resetData() {
        let alert = NSAlert()
        alert.messageText = languageManager.text(.resetTitle)
        alert.informativeText = languageManager.text(.resetMessage)
        alert.addButton(withTitle: languageManager.text(.reset))
        alert.addButton(withTitle: languageManager.text(.cancel))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        stopPasteRail()
        do {
            try ClipStore.resetApplicationData()
        } catch {
            print("Reset failure: \(error)")
            let errorAlert = NSAlert()
            errorAlert.messageText = languageManager.text(.resetFailedTitle)
            errorAlert.informativeText = languageManager.text(.resetFailedMessage)
            errorAlert.addButton(withTitle: languageManager.text(.ok))
            errorAlert.runModal()
        }
        // Restart even when the reset failed, so the menu bar app never stays
        // without a store, panel, or shortcuts until the next launch.
        startPasteRail()
        rebuildMenu()
    }

    private func stopPasteRail() {
        panelController?.dismissPanel()
        model?.stop()
        model = nil
        panelController = nil
        panelHotKey = nil
        queueHotKey = nil
        openShortcutState.status = nil
        queueShortcutStatus = nil
    }

    private func showStorageError() {
        let alert = NSAlert()
        alert.messageText = languageManager.text(.storageErrorTitle)
        alert.informativeText = languageManager.text(.storageErrorMessage)
        alert.addButton(withTitle: languageManager.text(.ok))
        alert.runModal()
    }

    /// Returns the failed result when a menu selection could not register and the
    /// previous shortcut was kept active.
    @discardableResult
    private func registerOpenShortcut(_ shortcut: PasteRailShortcut, allowRollback: Bool) -> HotKeyRegistrationResult? {
        let previousState = openShortcutState
        let previousHotKey = panelHotKey
        panelHotKey = nil
        let result: HotKeyRegistrationResult
        do {
            panelHotKey = try HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, id: Self.openPanelHotKeyID) { [weak self] in
                self?.panelController?.toggle()
            }
            result = .success
        } catch {
            result = registrationResult(from: error)
            if allowRollback { panelHotKey = previousHotKey }
        }
        let resolution = OpenShortcutRegistrationPolicy.resolve(
            previous: previousState,
            requested: shortcut,
            result: result,
            allowRollback: allowRollback
        )
        openShortcutState = resolution.state
        PasteRailShortcut.current = resolution.state.shortcut
        print("Open panel hotkey id: \(Self.openPanelHotKeyID), registration result: \(shortcut.label): \(result.localizedMessage(language: .english, shortcutLabel: shortcut.label))")
        return resolution.rejectedResult
    }

    private func registerQueueShortcut() {
        do {
            queueHotKey = try HotKey(keyCode: 35, modifiers: UInt32(cmdKey | optionKey), id: Self.queueHotKeyID) { [weak self] in
                guard let self else { return }
                let target = self.pasteServiceTarget()
                self.model?.pasteNextQueueItem(target: target)
            }
            queueShortcutStatus = .success
        } catch {
            queueHotKey = nil
            queueShortcutStatus = registrationResult(from: error)
        }
        let label = PasteRailShortcut.queueLabel
        print("Queue hotkey id: \(Self.queueHotKeyID), registration result: \(label): \(HotKeyRegistrationResult.localizedStatus(queueShortcutStatus, language: .english, shortcutLabel: label))")
    }

    private func registrationResult(from error: Error) -> HotKeyRegistrationResult {
        guard case let HotKeyError.register(status) = error else { return .failed(-1) }
        return status == eventHotKeyExistsErr ? .conflict : .failed(status)
    }

    private func diagnosticsText() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let process = ProcessInfo.processInfo
        let architecture = Sysctl.machine
        return """
        PasteRail Diagnostics
        Version: \(version)
        Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")
        App path: \(Bundle.main.bundlePath)
        KeyStore type: \(PasteRailKeyStoreMode.current.rawValue)
        Language: \(languageManager.language.rawValue)
        Accessibility trusted: \(accessibilityManager.isTrusted())
        Open panel shortcut: \(openShortcut.label)
        Open panel hotkey id: \(Self.openPanelHotKeyID)
        Open panel shortcut status: \(openShortcut.label): \(HotKeyRegistrationResult.localizedStatus(openShortcutState.status, language: .english, shortcutLabel: openShortcut.label))
        Queue shortcut: \(PasteRailShortcut.queueLabel)
        Queue hotkey id: \(Self.queueHotKeyID)
        Queue shortcut status: \(PasteRailShortcut.queueLabel): \(HotKeyRegistrationResult.localizedStatus(queueShortcutStatus, language: .english, shortcutLabel: PasteRailShortcut.queueLabel))
        macOS version: \(process.operatingSystemVersionString)
        Architecture: \(architecture)
        """
    }

    @objc private func quit() {
        model?.stop()
        NSApp.terminate(nil)
    }
}

private enum Sysctl {
    static var machine: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var value = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &value, &size, nil, 0)
        return String(cString: value)
    }
}
