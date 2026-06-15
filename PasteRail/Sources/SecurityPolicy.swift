import AppKit
import Foundation

struct SecurityPolicy: Sendable {
    static let concealedType = "org.nspasteboard.ConcealedType"
    static let transientType = "org.nspasteboard.TransientType"

    var excludedBundlePrefixes: [String] = [
        "com.agilebits.onepassword",
        "com.1password.",
        "com.bitwarden.desktop",
        "com.lastpass.",
        "com.dashlane.",
        "com.apple.keychainaccess"
    ]

    func decision(types: [String], sourceBundleIdentifier: String?) -> CaptureDecision {
        if types.contains(Self.concealedType) || types.contains(Self.transientType) {
            return .reject("Protected pasteboard type")
        }
        guard let sourceBundleIdentifier else {
            return .reject("Unknown source application")
        }
        if excludedBundlePrefixes.contains(where: sourceBundleIdentifier.hasPrefix) {
            return .reject("Excluded source application")
        }
        return .capture
    }
}
