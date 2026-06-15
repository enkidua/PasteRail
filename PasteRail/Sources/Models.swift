import AppKit
import Foundation

enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text
    case richText
    case url
    case image
    case file

    var label: String {
        switch self {
        case .text: "Text"
        case .richText: "Rich Text"
        case .url: "URL"
        case .image: "Image"
        case .file: "File"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .richText: "textformat"
        case .url: "link"
        case .image: "photo"
        case .file: "doc"
        }
    }
}

struct ClipPayload: Codable, Equatable, Sendable {
    struct Representation: Codable, Equatable, Sendable {
        let pasteboardType: String
        let data: Data
    }

    let items: [[Representation]]

    var representations: [Representation] { items.flatMap { $0 } }

    var plainText: String? {
        let preferred = representations.first { $0.pasteboardType == NSPasteboard.PasteboardType.string.rawValue }
        return preferred.flatMap { String(data: $0.data, encoding: .utf8) }
    }
}

struct CapturedClip: Equatable, Sendable {
    let payload: ClipPayload
    let kind: ClipKind
    let title: String
    let searchText: String
}

struct SourceApplication: Equatable, Sendable {
    let name: String?
    let bundleIdentifier: String?
    let processIdentifier: pid_t
}

struct ClipRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var kind: ClipKind
    var title: String
    var searchText: String
    var createdAt: Date
    var sourceAppName: String?
    var sourceBundleIdentifier: String?
    var payloadFile: String
    var imageFile: String?
    var thumbnailFile: String?
    var digest: String?
    var isSensitive: Bool
    var isPinned: Bool
}

struct QueueEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let clipID: UUID
    var plainText: Bool
}

enum CaptureDecision: Equatable {
    case capture
    case reject(String)
}
