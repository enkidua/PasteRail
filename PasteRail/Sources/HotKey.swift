import Carbon
import Foundation

enum HotKeyError: Error, CustomStringConvertible {
    case installHandler(OSStatus)
    case register(OSStatus)

    var description: String {
        switch self {
        case let .installHandler(status):
            return "InstallEventHandler failed with OSStatus \(status)"
        case let .register(status):
            return "RegisterEventHotKey failed with OSStatus \(status)"
        }
    }
}

enum HotKeyRegistrationResult: Equatable {
    case success
    case conflict
    case failed(OSStatus)

    var isSuccess: Bool {
        self == .success
    }

    func localizedMessage(language: AppLanguage, shortcutLabel: String? = nil) -> String {
        let label = shortcutLabel ?? "Global shortcut"
        switch (language, self) {
        case (_, .success):
            return language == .korean ? "등록됨" : "Registered"
        case (_, .conflict):
            return language == .korean
                ? "\(label)가 다른 앱에서 이미 사용 중입니다. 충돌 앱을 종료하거나 단축키를 변경해 주세요."
                : "\(label) is already used by another app. Please change the shortcut or close the conflicting app."
        case let (_, .failed(status)):
            return language == .korean
                ? "\(label) 전역 단축키 등록에 실패했습니다. 오류 코드: \(status)"
                : "\(label) global shortcut registration failed. Error code: \(status)"
        }
    }
}

extension HotKeyRegistrationResult {
    static func localizedStatus(
        _ status: HotKeyRegistrationResult?,
        language: AppLanguage,
        shortcutLabel: String
    ) -> String {
        guard let status else {
            return language == .korean ? "등록되지 않음" : "Not registered"
        }
        return status.localizedMessage(language: language, shortcutLabel: shortcutLabel)
    }
}

/// The open-panel shortcut that is actually active. `status` is nil when no
/// registration has been attempted, for example after the store failed to open.
struct OpenShortcutState: Equatable {
    var shortcut: PasteRailShortcut
    var status: HotKeyRegistrationResult?
}

struct OpenShortcutResolution: Equatable {
    let state: OpenShortcutState
    /// Set when a menu selection failed and the previous shortcut stayed active.
    let rejectedResult: HotKeyRegistrationResult?
}

enum OpenShortcutRegistrationPolicy {
    static func resolve(
        previous: OpenShortcutState,
        requested: PasteRailShortcut,
        result: HotKeyRegistrationResult,
        allowRollback: Bool
    ) -> OpenShortcutResolution {
        if result.isSuccess {
            return OpenShortcutResolution(
                state: OpenShortcutState(shortcut: requested, status: .success),
                rejectedResult: nil
            )
        }
        if allowRollback {
            return OpenShortcutResolution(state: previous, rejectedResult: result)
        }
        return OpenShortcutResolution(
            state: OpenShortcutState(shortcut: requested, status: result),
            rejectedResult: nil
        )
    }
}

/// Warnings are derived from the current registration state instead of being stored as
/// text, so each one disappears only when its own shortcut registers and always follows
/// the selected language.
enum HotKeyWarnings {
    static func messages(
        open: OpenShortcutState,
        queueStatus: HotKeyRegistrationResult?,
        language: AppLanguage
    ) -> [String] {
        var messages: [String] = []
        if let status = open.status, !status.isSuccess {
            messages.append(status.localizedMessage(language: language, shortcutLabel: open.shortcut.label))
        }
        if let queueStatus, !queueStatus.isSuccess {
            messages.append(queueStatus.localizedMessage(language: language, shortcutLabel: PasteRailShortcut.queueLabel))
        }
        return messages
    }
}

struct ShortcutSelectionDecision {
    static func shouldRegister(
        current: PasteRailShortcut,
        requested: PasteRailShortcut,
        currentStatus: HotKeyRegistrationResult? = .success
    ) -> Bool {
        current != requested || currentStatus?.isSuccess != true
    }
}

enum PasteRailShortcut: String, CaseIterable {
    case commandShiftV
    case commandOptionV
    case controlOptionV
    case controlOptionSpace

    static let defaultsKey = "PasteRail.OpenPanelShortcut"
    static let queueLabel = "Command + Option + P"

    static var current: PasteRailShortcut {
        get {
            if let raw = UserDefaults.standard.string(forKey: defaultsKey),
               let shortcut = PasteRailShortcut(rawValue: raw) {
                return shortcut
            }
            return .commandShiftV
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    var label: String {
        switch self {
        case .commandShiftV: "Command + Shift + V"
        case .commandOptionV: "Command + Option + V"
        case .controlOptionV: "Control + Option + V"
        case .controlOptionSpace: "Control + Option + Space"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .commandShiftV, .commandOptionV, .controlOptionV:
            return 9
        case .controlOptionSpace:
            return 49
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .commandShiftV:
            return UInt32(cmdKey | shiftKey)
        case .commandOptionV:
            return UInt32(cmdKey | optionKey)
        case .controlOptionV, .controlOptionSpace:
            return UInt32(controlKey | optionKey)
        }
    }
}

@MainActor
final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let expectedID: UInt32
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, id: UInt32, action: @escaping () -> Void) throws {
        expectedID = id
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            let parameterStatus = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard parameterStatus == noErr else {
                print("Hotkey event ignored: failed to read EventHotKeyID \(parameterStatus)")
                return OSStatus(eventNotHandledErr)
            }
            let instance = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            guard HotKey.shouldHandleEvent(expectedID: instance.expectedID, actualID: hotKeyID.id) else {
                print("Hotkey event ignored: expected id \(instance.expectedID), received id \(hotKeyID.id)")
                return OSStatus(eventNotHandledErr)
            }
            Task { @MainActor in instance.action() }
            return noErr
        }, 1, &eventType, pointer, &handler)
        guard handlerStatus == noErr else { throw HotKeyError.installHandler(handlerStatus) }
        let hotKeyID = EventHotKeyID(signature: OSType(0x5052414C), id: id)
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference)
        guard registerStatus == noErr else {
            print("Hotkey registration failure: \(registerStatus)")
            throw HotKeyError.register(registerStatus)
        }
        print("Hotkey registration success: id \(id)")
    }

    static func shouldHandleEvent(expectedID: UInt32, actualID: UInt32) -> Bool {
        expectedID == actualID
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
