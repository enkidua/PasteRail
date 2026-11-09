import Combine
import Foundation

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case korean = "ko"

    var displayName: String {
        switch self {
        case .english: "English"
        case .korean: "한국어"
        }
    }
}

final class AppLanguageManager: ObservableObject {
    static let shared = AppLanguageManager()
    static let defaultsKey = "selectedLanguage"

    private let defaults: UserDefaults
    @Published private var selectedLanguage: AppLanguage

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.defaultsKey),
           let language = AppLanguage(rawValue: raw) {
            selectedLanguage = language
        } else {
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
            selectedLanguage = preferred.hasPrefix("ko") ? .korean : .english
        }
    }

    var language: AppLanguage {
        get {
            selectedLanguage
        }
        set {
            selectedLanguage = newValue
            defaults.set(newValue.rawValue, forKey: Self.defaultsKey)
        }
    }

    func text(_ key: TextKey) -> String {
        switch (language, key) {
        case (.english, .openPasteRail): "Open PasteRail"
        case (.korean, .openPasteRail): "PasteRail 열기"
        case (.english, .showWelcome): "Show Welcome"
        case (.korean, .showWelcome): "시작 안내 보기"
        case (.english, .pasteNextQueueItem): "Paste Next Queue Item"
        case (.korean, .pasteNextQueueItem): "큐 다음 항목 붙여넣기"
        case (.english, .openAccessibilitySettings): "Open Accessibility Settings"
        case (.korean, .openAccessibilitySettings): "손쉬운 사용 설정 열기"
        case (.english, .requestAccessibilityPermission): "Request Accessibility Permission"
        case (.korean, .requestAccessibilityPermission): "손쉬운 사용 권한 요청"
        case (.english, .resetData): "Reset PasteRail Data"
        case (.korean, .resetData): "PasteRail 데이터 초기화"
        case (.english, .language): "Language"
        case (.korean, .language): "언어"
        case (.english, .shortcut): "Shortcut"
        case (.korean, .shortcut): "단축키"
        case (.english, .copyDiagnostics): "Copy Diagnostics"
        case (.korean, .copyDiagnostics): "진단 정보 복사"
        case (.english, .quit): "Quit PasteRail"
        case (.korean, .quit): "PasteRail 종료"
        case (.english, .welcomeTitle): "PasteRail is running in the menu bar."
        case (.korean, .welcomeTitle): "PasteRail이 메뉴바에서 실행 중입니다."
        case (.english, .welcomeQueueShortcut): "Press Command + Option + P to paste the next queue item."
        case (.korean, .welcomeQueueShortcut): "Command + Option + P를 눌러 큐의 다음 항목을 붙여넣으세요."
        case (.english, .welcomeLocalStorage): "Clipboard history is stored locally."
        case (.korean, .welcomeLocalStorage): "클립보드 기록은 이 Mac에만 저장됩니다."
        case (.english, .welcomeNotNotarized): "This beta build is not notarized."
        case (.korean, .welcomeNotNotarized): "이 베타 빌드는 공증되지 않았습니다."
        case (.english, .dontShowAgain): "Don't show again"
        case (.korean, .dontShowAgain): "다시 보지 않기"
        case (.english, .openClipboardPanel): "Open Clipboard Panel"
        case (.korean, .openClipboardPanel): "클립보드 패널 열기"
        case (.english, .ok): "OK"
        case (.korean, .ok): "확인"
        case (.english, .cancel): "Cancel"
        case (.korean, .cancel): "취소"
        case (.english, .reset): "Reset"
        case (.korean, .reset): "초기화"
        case (.english, .resetTitle): "Reset PasteRail data?"
        case (.korean, .resetTitle): "PasteRail 데이터를 초기화할까요?"
        case (.english, .resetMessage): "This deletes PasteRail clipboard history and local encryption keys from ~/Library/Application Support/PasteRail, and data left by the first test build in ~/Library/Application Support/io.pasterail.PasteRail. It does not delete any Keychain items from older test builds."
        case (.korean, .resetMessage): "~/Library/Application Support/PasteRail의 클립보드 기록과 로컬 암호화 키, 그리고 첫 테스트 빌드가 남긴 ~/Library/Application Support/io.pasterail.PasteRail 데이터를 삭제합니다. 이전 테스트 빌드의 Keychain 항목은 삭제하지 않습니다."
        case (.english, .resetFailedTitle): "PasteRail could not reset its local data."
        case (.korean, .resetFailedTitle): "PasteRail 로컬 데이터를 초기화하지 못했습니다."
        case (.english, .resetFailedMessage): "Check permissions for the PasteRail folders in ~/Library/Application Support and try again."
        case (.korean, .resetFailedMessage): "~/Library/Application Support 안의 PasteRail 폴더 권한을 확인한 뒤 다시 시도하세요."
        case (.english, .storageErrorTitle): "PasteRail could not open its local history."
        case (.korean, .storageErrorTitle): "PasteRail 로컬 기록을 열 수 없습니다."
        case (.english, .storageErrorMessage): "Records from an earlier test build may use a different encryption key. PasteRail did not delete anything. Use Reset PasteRail Data from the menu bar if you want to initialize the local store and start again."
        case (.korean, .storageErrorMessage): "이전 테스트 빌드의 기록이 다른 암호화 키를 사용했을 수 있습니다. PasteRail은 아무 데이터도 삭제하지 않았습니다. 새로 시작하려면 메뉴바에서 PasteRail 데이터 초기화를 선택하세요."
        case (.english, .accessibilityHelp): "Allow PasteRail in Accessibility settings. Do not run PasteRail.app directly from the DMG; copy it to /Applications, relaunch it, and click this button again if it does not appear. macOS requires you to enable it manually. PasteRail cannot silently add itself to the list."
        case (.korean, .accessibilityHelp): "PasteRail.app을 DMG 안에서 바로 실행하지 말고 /Applications 폴더로 복사한 뒤 실행해 주세요. 목록에 보이지 않으면 다시 실행하고 이 버튼을 다시 눌러 주세요. macOS 손쉬운 사용 목록에는 사용자가 직접 허용해야 하며, 앱이 자기 자신을 조용히 추가할 수는 없습니다."
        case (.english, .accessibilityPasteRequired): "Automatic paste requires Accessibility permission. You can still open PasteRail from the menu bar."
        case (.korean, .accessibilityPasteRequired): "붙여넣기 자동 실행에는 손쉬운 사용 권한이 필요합니다. 메뉴바에서 PasteRail 패널은 계속 열 수 있습니다."
        case (.english, .diagnosticsCopied): "PasteRail diagnostics were copied."
        case (.korean, .diagnosticsCopied): "PasteRail 진단 정보를 복사했습니다."
        case (.english, .hotKeyWarningTitle): "PasteRail is running, but a shortcut could not be registered."
        case (.korean, .hotKeyWarningTitle): "PasteRail은 실행 중이지만 단축키를 등록하지 못했습니다."
        case (.english, .searchClipboardHistory): "Search clipboard history"
        case (.korean, .searchClipboardHistory): "클립보드 기록 검색"
        case (.english, .queueSelected): "Queue Selected"
        case (.korean, .queueSelected): "선택 항목 큐에 추가"
        case (.english, .plainTextQueue): "Plain Text Queue"
        case (.korean, .plainTextQueue): "일반 텍스트 큐"
        case (.english, .historyType): "History type"
        case (.korean, .historyType): "기록 유형"
        case (.english, .historyLimitNotice): "Stores up to 100 recent items"
        case (.korean, .historyLimitNotice): "최근 기록 최대 100개 저장"
        case (.english, .noClipboardHistory): "No Clipboard History"
        case (.korean, .noClipboardHistory): "클립보드 기록 없음"
        case (.english, .emptyHistoryHelp): "Copy something or change the current search and filter."
        case (.korean, .emptyHistoryHelp): "무언가를 복사하거나 현재 검색과 필터를 바꿔 보세요."
        case (.english, .queueEmpty): "Queue empty"
        case (.korean, .queueEmpty): "큐 비어 있음"
        case (.english, .current): "Current"
        case (.korean, .current): "현재"
        case (.english, .next): "Next"
        case (.korean, .next): "다음"
        case (.english, .previous): "Previous"
        case (.korean, .previous): "이전"
        case (.english, .restart): "Restart"
        case (.korean, .restart): "다시 시작"
        case (.english, .skip): "Skip"
        case (.korean, .skip): "건너뛰기"
        case (.english, .pasteNext): "Paste Next"
        case (.korean, .pasteNext): "다음 붙여넣기"
        case (.english, .clear): "Clear"
        case (.korean, .clear): "비우기"
        case (.english, .unknownApplication): "Unknown application"
        case (.korean, .unknownApplication): "알 수 없는 앱"
        case (.english, .selectForQueue): "Select for queue"
        case (.korean, .selectForQueue): "큐 선택"
        case (.english, .removeFromQueueSelection): "Remove from queue selection"
        case (.korean, .removeFromQueueSelection): "큐 선택 해제"
        case (.english, .selectForQueueHint): "Changes queue selection without pasting this item."
        case (.korean, .selectForQueueHint): "이 항목을 붙여넣지 않고 큐 선택만 변경합니다."
        case (.english, .pasteItemHint): "Pastes this item into the target application."
        case (.korean, .pasteItemHint): "이 항목을 대상 앱에 붙여넣습니다."
        case (.english, .pinItem): "Pin item"
        case (.korean, .pinItem): "항목 고정"
        case (.english, .unpinItem): "Unpin item"
        case (.korean, .unpinItem): "항목 고정 해제"
        case (.english, .pinItemHint): "Changes pinned state without pasting this item."
        case (.korean, .pinItemHint): "이 항목을 붙여넣지 않고 고정 상태만 변경합니다."
        case (.english, .inPasteQueue): "In paste queue"
        case (.korean, .inPasteQueue): "붙여넣기 큐에 있음"
        case (.english, .imagePreviewUnavailable): "Image preview unavailable"
        case (.korean, .imagePreviewUnavailable): "이미지 미리보기를 사용할 수 없음"
        case (.english, .openShortcutStatus): "Open panel shortcut status"
        case (.korean, .openShortcutStatus): "패널 단축키 상태"
        case (.english, .settingsPrivacy): "Clipboard history stays on this Mac. PasteRail contains no network client, analytics, ads, or update service."
        case (.korean, .settingsPrivacy): "클립보드 기록은 이 Mac에만 저장됩니다. PasteRail에는 네트워크 클라이언트, 분석, 광고, 업데이트 서비스가 없습니다."
        case (.english, .captureHistoryLimit): "PasteRail stores up to 100 recent items. All current items are pinned, so the new item was not saved."
        case (.korean, .captureHistoryLimit): "PasteRail은 최근 항목을 최대 100개까지 저장합니다. 현재 항목이 모두 고정되어 있어 새 항목을 저장하지 않았습니다."
        case (.english, .captureStorageLimit): "PasteRail uses up to 500 MiB for clipboard files. Pinned items prevent enough space from being freed, so the new item was not saved."
        case (.korean, .captureStorageLimit): "PasteRail은 클립보드 파일에 최대 500MiB를 사용합니다. 고정된 항목 때문에 공간을 충분히 확보하지 못해 새 항목을 저장하지 않았습니다."
        case (.english, .captureFailed): "PasteRail could not safely store this clipboard item."
        case (.korean, .captureFailed): "이 클립보드 항목을 안전하게 저장하지 못했습니다."
        case (.english, .pinChangeFailed): "PasteRail could not save the pin change."
        case (.korean, .pinChangeFailed): "고정 상태 변경을 저장하지 못했습니다."
        case (.english, .clipboardItemLoadFailed): "PasteRail could not load this clipboard item."
        case (.korean, .clipboardItemLoadFailed): "이 클립보드 항목을 불러오지 못했습니다."
        case (.english, .queueSaveFailed): "The paste queue could not be saved."
        case (.korean, .queueSaveFailed): "붙여넣기 큐를 저장하지 못했습니다."
        case (.english, .queueItemLoadFailed): "PasteRail could not load this queue item. The queue position was preserved."
        case (.korean, .queueItemLoadFailed): "이 큐 항목을 불러오지 못했습니다. 큐 위치는 그대로 유지했습니다."
        case (.english, .queueAdvanceFailed): "Paste was sent, but queue progress could not be saved. The queue position was preserved."
        case (.korean, .queueAdvanceFailed): "붙여넣기는 실행했지만 큐 진행 상태를 저장하지 못했습니다. 큐 위치는 그대로 유지했습니다."
        case (.english, .queueChangeFailed): "The paste queue change could not be saved. The previous queue was kept."
        case (.korean, .queueChangeFailed): "붙여넣기 큐 변경을 저장하지 못했습니다. 이전 큐를 유지했습니다."
        case (.english, .pasteEventFailedRestored): "Paste shortcut delivery failed. The previous clipboard contents were restored."
        case (.korean, .pasteEventFailedRestored): "붙여넣기 단축키를 보내지 못했습니다. 이전 클립보드 내용을 복원했습니다."
        case (.english, .pasteEventFailedLost): "Paste shortcut delivery failed, and PasteRail could not restore the previous clipboard contents."
        case (.korean, .pasteEventFailedLost): "붙여넣기 단축키를 보내지 못했고, 이전 클립보드 내용도 복원하지 못했습니다."
        case (.english, .pasteWriteFailedRestored): "PasteRail could not write this item. The previous clipboard contents were restored."
        case (.korean, .pasteWriteFailedRestored): "이 항목을 클립보드에 쓰지 못했습니다. 이전 클립보드 내용을 복원했습니다."
        case (.english, .pasteWriteFailedLost): "PasteRail could not write this item or restore the previous clipboard contents."
        case (.korean, .pasteWriteFailedLost): "이 항목을 클립보드에 쓰지 못했고, 이전 클립보드 내용도 복원하지 못했습니다."
        case (.english, .pasteNoWritableRepresentation): "This item has no writable representation."
        case (.korean, .pasteNoWritableRepresentation): "이 항목에는 붙여넣을 수 있는 형식이 없습니다."
        case (.english, .pasteTargetUnavailable): "The previous application is no longer available."
        case (.korean, .pasteTargetUnavailable): "붙여넣을 앱이 더 이상 실행 중이 아닙니다."
        case (.english, .pasteTargetActivationFailed): "PasteRail could not restore the target application."
        case (.korean, .pasteTargetActivationFailed): "붙여넣을 앱으로 다시 전환하지 못했습니다."
        case (.english, .recoveryIndexRestored): "Clipboard history index was damaged. PasteRail preserved the encrypted file and restored the last backup."
        case (.korean, .recoveryIndexRestored): "클립보드 기록 색인이 손상되었습니다. 암호화된 파일은 보존하고 마지막 백업을 복원했습니다."
        case (.english, .recoveryPinnedStorageLimit): "Stored pinned clipboard records exceed the storage limit. PasteRail preserved them and will reject new records until space is available."
        case (.korean, .recoveryPinnedStorageLimit): "고정된 클립보드 기록이 저장 한도를 넘었습니다. 기존 기록은 보존하며, 공간이 생길 때까지 새 기록은 저장하지 않습니다."
        case (.english, .recoveryPinnedHistoryLimit): "More than 100 stored records are pinned. PasteRail preserved them and will reject new records until records are unpinned or removed."
        case (.korean, .recoveryPinnedHistoryLimit): "고정된 기록이 100개를 넘었습니다. 기존 기록은 보존하며, 고정을 해제하거나 삭제할 때까지 새 기록은 저장하지 않습니다."
        case (.english, .recoveryPlaintextCleanupPending): "Encrypted history is available, but secure plaintext cleanup could not be completed. It will be retried."
        case (.korean, .recoveryPlaintextCleanupPending): "암호화된 기록은 사용할 수 있지만 평문 파일 정리를 끝내지 못했습니다. 다음 실행 때 다시 시도합니다."
        }
    }

    func welcomeOpenShortcut(_ shortcutLabel: String) -> String {
        switch language {
        case .english: "Press \(shortcutLabel) to open clipboard history."
        case .korean: "\(shortcutLabel)를 눌러 클립보드 기록을 여세요."
        }
    }

    func message(for result: PasteResult) -> String? {
        switch result {
        case .eventSent: nil
        case .eventFailedPreviousRestored: text(.pasteEventFailedRestored)
        case .eventFailedPreviousLost: text(.pasteEventFailedLost)
        case .newWriteFailedPreviousRestored: text(.pasteWriteFailedRestored)
        case .newWriteFailedPreviousLost: text(.pasteWriteFailedLost)
        case .preparationFailed(.noWritableRepresentation): text(.pasteNoWritableRepresentation)
        case .preparationFailed(.accessibilityRequired): text(.accessibilityPasteRequired)
        case .preparationFailed(.targetUnavailable): text(.pasteTargetUnavailable)
        case .preparationFailed(.targetActivationFailed): text(.pasteTargetActivationFailed)
        }
    }

    func message(for notice: StoreRecoveryNotice) -> String {
        switch notice {
        case .indexRestoredFromBackup: text(.recoveryIndexRestored)
        case .pinnedRecordsExceedStorageLimit: text(.recoveryPinnedStorageLimit)
        case .pinnedRecordsExceedHistoryLimit: text(.recoveryPinnedHistoryLimit)
        case .plaintextCleanupPending: text(.recoveryPlaintextCleanupPending)
        }
    }

    enum TextKey: CaseIterable {
        case openPasteRail
        case showWelcome
        case pasteNextQueueItem
        case openAccessibilitySettings
        case requestAccessibilityPermission
        case resetData
        case language
        case shortcut
        case copyDiagnostics
        case quit
        case welcomeTitle
        case welcomeQueueShortcut
        case welcomeLocalStorage
        case welcomeNotNotarized
        case dontShowAgain
        case openClipboardPanel
        case ok
        case cancel
        case reset
        case resetTitle
        case resetMessage
        case resetFailedTitle
        case resetFailedMessage
        case storageErrorTitle
        case storageErrorMessage
        case accessibilityHelp
        case accessibilityPasteRequired
        case diagnosticsCopied
        case hotKeyWarningTitle
        case searchClipboardHistory
        case queueSelected
        case plainTextQueue
        case historyType
        case historyLimitNotice
        case noClipboardHistory
        case emptyHistoryHelp
        case queueEmpty
        case current
        case next
        case previous
        case restart
        case skip
        case pasteNext
        case clear
        case unknownApplication
        case selectForQueue
        case removeFromQueueSelection
        case selectForQueueHint
        case pasteItemHint
        case pinItem
        case unpinItem
        case pinItemHint
        case inPasteQueue
        case imagePreviewUnavailable
        case openShortcutStatus
        case settingsPrivacy
        case captureHistoryLimit
        case captureStorageLimit
        case captureFailed
        case pinChangeFailed
        case clipboardItemLoadFailed
        case queueSaveFailed
        case queueItemLoadFailed
        case queueAdvanceFailed
        case queueChangeFailed
        case pasteEventFailedRestored
        case pasteEventFailedLost
        case pasteWriteFailedRestored
        case pasteWriteFailedLost
        case pasteNoWritableRepresentation
        case pasteTargetUnavailable
        case pasteTargetActivationFailed
        case recoveryIndexRestored
        case recoveryPinnedStorageLimit
        case recoveryPinnedHistoryLimit
        case recoveryPlaintextCleanupPending
    }
}
