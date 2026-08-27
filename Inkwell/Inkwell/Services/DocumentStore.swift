import Foundation
import UniformTypeIdentifiers

enum DocumentStoreError: LocalizedError {
    case couldNotAccessFile
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .couldNotAccessFile:
            return "The file couldn't be opened. If it's in iCloud Drive, download it first and try again."
        case .copyFailed(let message):
            return "Couldn't file that document: \(message)"
        }
    }
}

/// Owns the on-disk copies of imported documents.
///
/// Files are copied into the app's own Documents directory rather than
/// referenced in place, so a document stays readable after the original is
/// moved, renamed, or removed from iCloud Drive. The directory is the app's
/// visible Documents folder, which means the whole library is also browsable
/// from the Files app on iPad and from Finder on the Mac.
struct DocumentStore {
    static let shared = DocumentStore()

    private let folderName = "Library"

    private var root: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    func url(forRelativePath relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    /// Copies a user-picked file into the store and returns the metadata needed
    /// to build a `StoredDocument`.
    ///
    /// `sourceURL` is expected to be a security-scoped URL from a document
    /// picker; the scope is opened and closed around the copy.
    func importFile(at sourceURL: URL) throws -> ImportedFile {
        let didScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if didScope { sourceURL.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            throw DocumentStoreError.couldNotAccessFile
        }

        let originalFilename = sourceURL.lastPathComponent
        let relativePath = uniqueRelativePath(for: originalFilename)
        let destination = url(forRelativePath: relativePath)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            throw DocumentStoreError.copyFailed(error.localizedDescription)
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
        let byteCount = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        let type = UTType(filenameExtension: sourceURL.pathExtension)

        return ImportedFile(
            relativePath: relativePath,
            originalFilename: originalFilename,
            suggestedTitle: sourceURL.deletingPathExtension().lastPathComponent,
            kind: DocumentKind.kind(for: type),
            byteCount: byteCount
        )
    }

    /// Writes raw bytes into the store — used for scans and photo imports,
    /// which arrive as data rather than as a file on disk.
    func importData(_ data: Data, filename: String, kind: DocumentKind) throws -> ImportedFile {
        let relativePath = uniqueRelativePath(for: filename)
        let destination = url(forRelativePath: relativePath)
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw DocumentStoreError.copyFailed(error.localizedDescription)
        }
        return ImportedFile(
            relativePath: relativePath,
            originalFilename: filename,
            suggestedTitle: (filename as NSString).deletingPathExtension,
            kind: kind,
            byteCount: data.count
        )
    }

    func delete(relativePath: String) {
        try? FileManager.default.removeItem(at: url(forRelativePath: relativePath))
    }

    /// Prefixes a UUID so two files named `syllabus.pdf` can coexist, while
    /// keeping the readable name in the path for anyone browsing in Files.
    private func uniqueRelativePath(for filename: String) -> String {
        let safeName = filename
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = UUID().uuidString.prefix(8)
        return "\(stem)-\(safeName.isEmpty ? "document" : safeName)"
    }
}

/// The result of copying a file into the store.
struct ImportedFile {
    let relativePath: String
    let originalFilename: String
    let suggestedTitle: String
    let kind: DocumentKind
    let byteCount: Int
}
