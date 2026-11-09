import os

/// Unified-log channels. `log stream --predicate 'process == "PasteRail"' --level debug`
/// shows them for any launch, including from Finder, where print output is lost.
/// Messages carry app state only, never clipboard contents.
enum PasteRailLog {
    static let app = Logger(subsystem: "io.pasterail.PasteRail", category: "app")
    static let hotKey = Logger(subsystem: "io.pasterail.PasteRail", category: "hotkey")
}
