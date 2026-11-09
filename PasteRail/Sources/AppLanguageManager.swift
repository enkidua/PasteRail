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
        case (.english, .welcomeOpenShortcut): "Press Command-Shift-V to open clipboard history."
        case (.korean, .welcomeOpenShortcut): "Command-Shift-V를 눌러 클립보드 기록을 여세요."
        case (.english, .welcomeQueueShortcut): "Press Command-Option-P to paste the next queue item."
        case (.korean, .welcomeQueueShortcut): "Command-Option-P를 눌러 큐의 다음 항목을 붙여넣으세요."
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
        case (.english, .resetMessage): "This deletes PasteRail clipboard history and local encryption keys from ~/Library/Application Support/PasteRail. It does not delete any Keychain items from older test builds."
        case (.korean, .resetMessage): "~/Library/Application Support/PasteRail의 클립보드 기록과 로컬 암호화 키를 삭제합니다. 이전 테스트 빌드의 Keychain 항목은 삭제하지 않습니다."
        case (.english, .resetFailedTitle): "PasteRail could not reset its local data."
        case (.korean, .resetFailedTitle): "PasteRail 로컬 데이터를 초기화하지 못했습니다."
        case (.english, .resetFailedMessage): "Check permissions for ~/Library/Application Support/PasteRail and try again."
        case (.korean, .resetFailedMessage): "~/Library/Application Support/PasteRail 권한을 확인한 뒤 다시 시도하세요."
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
        case (.english, .sensitiveContent): "Sensitive content"
        case (.korean, .sensitiveContent): "민감한 내용"
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
        }
    }

    enum TextKey {
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
        case welcomeOpenShortcut
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
        case sensitiveContent
        case selectForQueue
        case removeFromQueueSelection
        case selectForQueueHint
        case pasteItemHint
        case pinItem
        case unpinItem
        case pinItemHint
        case inPasteQueue
        case imagePreviewUnavailable
    }
}
