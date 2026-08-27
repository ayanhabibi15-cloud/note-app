import Foundation
import SwiftData
import UniformTypeIdentifiers

/// What kind of file a document is, which decides both how its text gets
/// extracted and which icon the library shows.
enum DocumentKind: String, Codable, CaseIterable {
    case pdf
    case image
    case text
    case other

    var symbolName: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .text: return "doc.plaintext"
        case .other: return "doc"
        }
    }

    static func kind(for type: UTType?) -> DocumentKind {
        guard let type else { return .other }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .text) || type.conforms(to: .plainText) { return .text }
        return .other
    }
}

/// A file the user has filed into the app: a syllabus, a problem set, a
/// permission slip, a project spec. The bytes live on disk under the app's
/// Documents directory (see `DocumentStore`); this model holds the metadata
/// plus the extracted plain text, which is what the assistant actually reads.
@Model
final class StoredDocument {
    var title: String
    /// Path relative to the store's root directory. Kept relative because the
    /// app container's absolute path changes between launches and devices.
    var relativePath: String
    var originalFilename: String
    var kindRawValue: String
    var areaRawValue: String
    var course: String
    var notes: String
    var byteCount: Int
    var pageCount: Int
    var addedAt: Date
    /// Plain text pulled out of the file so Claude can read it without the
    /// file ever being uploaded anywhere. Empty until extraction finishes.
    var extractedText: String
    var extractionFailed: Bool
    /// When true, this document is offered to the assistant as context by
    /// default. Off for large or irrelevant files so prompts stay small.
    var isPinnedToAssistant: Bool

    var kind: DocumentKind {
        get { DocumentKind(rawValue: kindRawValue) ?? .other }
        set { kindRawValue = newValue.rawValue }
    }

    var area: LifeArea {
        get { LifeArea.from(areaRawValue) }
        set { areaRawValue = newValue.rawValue }
    }

    init(
        title: String,
        relativePath: String,
        originalFilename: String,
        kind: DocumentKind,
        area: LifeArea = .personal,
        course: String = "",
        byteCount: Int = 0
    ) {
        self.title = title
        self.relativePath = relativePath
        self.originalFilename = originalFilename
        self.kindRawValue = kind.rawValue
        self.areaRawValue = area.rawValue
        self.course = course
        self.notes = ""
        self.byteCount = byteCount
        self.pageCount = 0
        self.addedAt = .now
        self.extractedText = ""
        self.extractionFailed = false
        self.isPinnedToAssistant = false
    }

    var fileURL: URL {
        DocumentStore.shared.url(forRelativePath: relativePath)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    var hasText: Bool {
        !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
