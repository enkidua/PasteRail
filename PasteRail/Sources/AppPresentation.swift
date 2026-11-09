import AppKit
import Foundation
import Security

/// Builds the Welcome dialog text from the current shortcut state, so the dialog
/// always names the shortcut that is actually selected.
enum WelcomeContent {
    static func lines(
        languageManager: AppLanguageManager,
        openShortcut: OpenShortcutState,
        queueStatus: HotKeyRegistrationResult?,
        isDeveloperIDSigned: Bool
    ) -> [String] {
        let language = languageManager.language
        var lines = [
            languageManager.welcomeOpenShortcut(openShortcut.shortcut.label),
            languageManager.text(.welcomeQueueShortcut),
            languageManager.text(.welcomeLocalStorage)
        ]
        if !isDeveloperIDSigned {
            lines.append(languageManager.text(.welcomeNotNotarized))
        }
        // A failed registration is explained by its warning below, so the status
        // line is shown only for a registered or not-yet-attempted shortcut.
        if openShortcut.status?.isSuccess != false {
            let status = HotKeyRegistrationResult.localizedStatus(
                openShortcut.status,
                language: language,
                shortcutLabel: openShortcut.shortcut.label
            )
            lines.append("\(languageManager.text(.openShortcutStatus)): \(status)")
        }
        lines.append(contentsOf: HotKeyWarnings.messages(open: openShortcut, queueStatus: queueStatus, language: language))
        return lines
    }
}

enum DistributionSignature {
    /// Apple's designated requirement for Developer ID Application signatures. It is
    /// checked locally against the running code and never contacts Apple.
    private static let developerIDRequirement =
        "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"

    /// True for a Developer ID release build. Ad-hoc manual-test builds return false.
    static let isDeveloperIDSigned: Bool = {
        var code: SecCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(developerIDRequirement as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }()
}

enum AppActivation {
    /// Brings PasteRail forward. macOS 14 replaced activate(ignoringOtherApps:) with
    /// cooperative activation, which still succeeds after a user-initiated shortcut.
    @MainActor
    static func activatePasteRail() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
