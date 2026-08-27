import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI

/// The document library.
///
/// Add a syllabus, a problem set, a permission slip, a project brief — the file
/// is copied into the app (so it survives the original being moved) and its
/// text is pulled out on device with PDFKit or Vision. That extracted text is
/// what the assistant reads, which is why a document you filed here can be
/// asked about without ever uploading the file itself.
struct DocumentsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \StoredDocument.addedAt, order: .reverse) private var documents: [StoredDocument]

    @State private var areaFilter: LifeArea?
    @State private var searchText = ""
    @State private var showFileImporter = false
    @State private var photoSelections: [PhotosPickerItem] = []
    @State private var importError: String?
    @State private var importingCount = 0
    @State private var selectedDocument: StoredDocument?

    private var filtered: [StoredDocument] {
        documents.filter { document in
            if let areaFilter, document.area != areaFilter { return false }
            guard !searchText.isEmpty else { return true }
            let needle = searchText.lowercased()
            return document.title.lowercased().contains(needle)
                || document.course.lowercased().contains(needle)
                || document.originalFilename.lowercased().contains(needle)
                || document.extractedText.lowercased().contains(needle)
        }
    }

    var body: some View {
        List {
            if importingCount > 0 {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading \(importingCount) file\(importingCount == 1 ? "" : "s")…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let importError {
                Section {
                    Label(importError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            ForEach(LifeArea.allCases) { area in
                let items = filtered.filter { $0.area == area }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { document in
                            DocumentRow(document: document)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedDocument = document }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        delete(document)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        document.isPinnedToAssistant.toggle()
                                    } label: {
                                        Label(
                                            document.isPinnedToAssistant ? "Unpin" : "Pin to Assistant",
                                            systemImage: document.isPinnedToAssistant ? "pin.slash" : "pin"
                                        )
                                    }
                                    .tint(.indigo)
                                }
                        }
                    } header: {
                        Label(area.title, systemImage: area.symbolName)
                    }
                }
            }

            if filtered.isEmpty && importingCount == 0 {
                ContentUnavailableView {
                    Label("No Documents", systemImage: "folder.badge.plus")
                } description: {
                    Text("Add PDFs, photos of handouts, or text files. Their text is read on this device so you can ask the assistant about them.")
                } actions: {
                    Button("Add Files") { showFileImporter = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search documents and their contents")
        .navigationTitle("Documents")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Add Files…", systemImage: "doc.badge.plus")
                    }
                    PhotosPicker(selection: $photoSelections, matching: .images) {
                        Label("Add Photos…", systemImage: "photo.badge.plus")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Picker("Area", selection: $areaFilter) {
                    Text("All Areas").tag(LifeArea?.none)
                    ForEach(LifeArea.allCases) { area in
                        Label(area.title, systemImage: area.symbolName).tag(LifeArea?.some(area))
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .image, .plainText, .text, .rtf, .commaSeparatedText, .json, .data],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .onChange(of: photoSelections) { _, newValue in
            guard !newValue.isEmpty else { return }
            Task { await importPhotos(newValue) }
        }
        .sheet(item: $selectedDocument) { document in
            DocumentDetailView(document: document)
        }
    }

    // MARK: - Importing

    private func handleFileImport(_ result: Result<[URL], Error>) {
        importError = nil
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            for url in urls {
                do {
                    let imported = try DocumentStore.shared.importFile(at: url)
                    let document = StoredDocument(
                        title: imported.suggestedTitle,
                        relativePath: imported.relativePath,
                        originalFilename: imported.originalFilename,
                        kind: imported.kind,
                        area: areaFilter ?? .school,
                        byteCount: imported.byteCount
                    )
                    modelContext.insert(document)
                    Task { await extractText(for: document) }
                } catch {
                    importError = error.localizedDescription
                }
            }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        importError = nil
        photoSelections = []
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let filename = "Scan \(Date.now.formatted(date: .abbreviated, time: .shortened)).jpg"
                let imported = try DocumentStore.shared.importData(data, filename: filename, kind: .image)
                let document = StoredDocument(
                    title: imported.suggestedTitle,
                    relativePath: imported.relativePath,
                    originalFilename: imported.originalFilename,
                    kind: .image,
                    area: areaFilter ?? .school,
                    byteCount: imported.byteCount
                )
                modelContext.insert(document)
                await extractText(for: document)
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    /// Extraction runs off the main actor (OCR on a long PDF is slow) and the
    /// result is written back on the main actor, where the model context lives.
    private func extractText(for document: StoredDocument) async {
        importingCount += 1
        defer { importingCount -= 1 }

        let url = document.fileURL
        let kind = document.kind
        let result = await Task.detached(priority: .userInitiated) {
            await DocumentTextExtractor.extract(from: url, kind: kind)
        }.value

        document.extractedText = result.text
        document.pageCount = result.pageCount
        document.extractionFailed = result.failed
        // Small documents are cheap to include, so pin them by default; big
        // ones stay opt-in so a prompt never balloons by accident.
        document.isPinnedToAssistant = !result.failed && result.text.count < 8_000
    }

    private func delete(_ document: StoredDocument) {
        DocumentStore.shared.delete(relativePath: document.relativePath)
        modelContext.delete(document)
    }
}

struct DocumentRow: View {
    let document: StoredDocument

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: document.kind.symbolName)
                .font(.title2)
                .foregroundStyle(document.area.color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(document.formattedSize)
                    if document.pageCount > 1 {
                        Text("· \(document.pageCount) pages")
                    }
                    if !document.course.isEmpty {
                        Text("· \(document.course)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if document.extractionFailed {
                    Label("No readable text", systemImage: "eye.slash")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if document.hasText {
                    Text(document.extractedText.prefix(120))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if document.isPinnedToAssistant {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.indigo)
            }
        }
        .padding(.vertical, 2)
    }
}
