import SwiftUI
import SwiftData
import PDFKit
import UIKit

/// A single document: the file itself on one tab, the text the assistant can
/// read on the other. Showing the extracted text plainly is deliberate — it's
/// the only honest way to answer "how much of this can it actually see?", and
/// it makes a bad OCR pass obvious immediately.
struct DocumentDetailView: View {
    @Bindable var document: StoredDocument

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var tab = Tab.preview
    @State private var isReExtracting = false

    enum Tab: String, CaseIterable, Identifiable {
        case preview
        case text
        case details

        var id: String { rawValue }

        var title: String {
            switch self {
            case .preview: return "Preview"
            case .text: return "Extracted Text"
            case .details: return "Details"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                switch tab {
                case .preview: previewPane
                case .text: textPane
                case .details: detailsPane
                }
            }
            .navigationTitle(document.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: document.fileURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    // MARK: - Panes

    @ViewBuilder
    private var previewPane: some View {
        switch document.kind {
        case .pdf:
            PDFViewer(url: document.fileURL)
        case .image:
            ScrollView([.horizontal, .vertical]) {
                if let image = UIImage(contentsOfFile: document.fileURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                } else {
                    missingFileNotice
                }
            }
        case .text, .other:
            ScrollView {
                Text(fileText ?? "")
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    private var textPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isReExtracting {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading the document again…")
                            .foregroundStyle(.secondary)
                    }
                } else if document.hasText {
                    Text("\(document.extractedText.count) characters — this is exactly what the assistant sees.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(document.extractedText)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                } else {
                    ContentUnavailableView(
                        "No Text Yet",
                        systemImage: "text.viewfinder",
                        description: Text("Nothing readable was found in this file. Scanned pages sometimes need a second pass.")
                    )
                }

                Button {
                    Task { await reExtract() }
                } label: {
                    Label("Read It Again", systemImage: "arrow.clockwise")
                }
                .disabled(isReExtracting)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    private var detailsPane: some View {
        Form {
            Section("Name") {
                TextField("Title", text: $document.title)
                TextField("Notes about this document", text: $document.notes, axis: .vertical)
                    .lineLimit(2...6)
            }

            Section("Filing") {
                Picker("Area", selection: Binding(
                    get: { document.area },
                    set: { document.area = $0 }
                )) {
                    ForEach(LifeArea.allCases) { area in
                        Label(area.title, systemImage: area.symbolName).tag(area)
                    }
                }
                TextField("Class, club, or project", text: $document.course)
            }

            Section {
                Toggle("Share with the assistant by default", isOn: $document.isPinnedToAssistant)
                    .disabled(!document.hasText)
            } footer: {
                Text(document.hasText
                     ? "When on, this document's text is included with every assistant question in its area. Turn it off for long files you only occasionally need."
                     : "This document has no readable text, so there's nothing to share.")
            }

            Section("File") {
                LabeledContent("Original name", value: document.originalFilename)
                LabeledContent("Size", value: document.formattedSize)
                if document.pageCount > 0 {
                    LabeledContent("Pages", value: "\(document.pageCount)")
                }
                LabeledContent("Added", value: document.addedAt.formatted(date: .abbreviated, time: .shortened))
            }

            Section {
                Button(role: .destructive) {
                    DocumentStore.shared.delete(relativePath: document.relativePath)
                    modelContext.delete(document)
                    dismiss()
                } label: {
                    Label("Delete Document", systemImage: "trash")
                }
            }
        }
    }

    private var missingFileNotice: some View {
        ContentUnavailableView(
            "File Missing",
            systemImage: "doc.questionmark",
            description: Text("The stored copy of this file couldn't be opened.")
        )
    }

    private var fileText: String? {
        guard let data = try? Data(contentsOf: document.fileURL) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private func reExtract() async {
        isReExtracting = true
        let url = document.fileURL
        let kind = document.kind
        let result = await Task.detached(priority: .userInitiated) {
            await DocumentTextExtractor.extract(from: url, kind: kind)
        }.value
        document.extractedText = result.text
        document.pageCount = result.pageCount
        document.extractionFailed = result.failed
        isReExtracting = false
    }
}

/// PDFKit bridge. `PDFView` handles paging, zoom, and text selection for free,
/// which is more than a hand-rolled SwiftUI viewer would manage.
struct PDFViewer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
