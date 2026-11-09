import AppKit
import ApplicationServices
import Foundation

@MainActor
struct AccessibilityPermissionManager {
    private let languageManager: AppLanguageManager

    init(languageManager: AppLanguageManager = .shared) {
        self.languageManager = languageManager
    }

    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestPermissionPrompt() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func requestThenOpenSettings() {
        _ = requestPermissionPrompt()
        openAccessibilitySettings()
        showAccessibilityHelpIfNeeded()
    }

    func showAccessibilityHelpIfNeeded() {
        let alert = NSAlert()
        alert.messageText = languageManager.text(.requestAccessibilityPermission)
        alert.informativeText = languageManager.text(.accessibilityHelp)
        alert.addButton(withTitle: languageManager.text(.ok))
        AppActivation.activatePasteRail()
        alert.runModal()
    }
}
