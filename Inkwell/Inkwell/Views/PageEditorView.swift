import SwiftUI
import PencilKit
import SwiftData

enum EditorMode {
    case draw
    case text
}

struct PageEditorView: View {
    @Bindable var notebook: Notebook
    @Environment(\.modelContext) private var modelContext

    @State private var currentPageID: PersistentIdentifier?
    @State private var drawing = PKDrawing()
    @State private var mode: EditorMode = .draw
    @State private var pencilOnly = false
    @State private var showThumbnails = true
    @State private var showTemplateSheet = false
    @State private var showAIAssistant = false

    private var sortedPages: [Page] { notebook.sortedPages }

    private var currentPage: Page? {
        sortedPages.first { $0.persistentModelID == currentPageID } ?? sortedPages.first
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    TemplateBackgroundView(template: currentPage?.template ?? .blank)
                        .frame(width: PageSize.standard.width, height: PageSize.standard.height)
                        .background(Color.white)
                        .allowsHitTesting(false)

                    if let page = currentPage {
                        TextBoxLayerView(page: page, isEditing: mode == .text)
                    }

                    CanvasView(
                        drawing: $drawing,
                        isDrawingEnabled: mode == .draw,
                        pencilOnly: pencilOnly
                    ) { newDrawing in
                        persist(drawing: newDrawing)
                    }
                    .frame(width: PageSize.standard.width, height: PageSize.standard.height)
                }
                .shadow(radius: 2)
                .padding(24)
            }
            .background(Color(.secondarySystemBackground))

            if showThumbnails {
                Divider()
                PageThumbnailStrip(
                    notebook: notebook,
                    currentPageID: $currentPageID,
                    onSelect: { page in loadPage(page) }
                )
            }
        }
        .navigationTitle(notebook.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showAIAssistant = true
                } label: {
                    Label("Ask AI", systemImage: "sparkles")
                }

                Menu {
                    Button {
                        mode = .draw
                    } label: {
                        Label("Draw", systemImage: mode == .draw ? "checkmark" : "pencil.tip")
                    }
                    Button {
                        mode = .text
                    } label: {
                        Label("Add Text", systemImage: mode == .text ? "checkmark" : "textformat")
                    }
                    Toggle(isOn: $pencilOnly) {
                        Label("Apple Pencil Only", systemImage: "pencil.and.outline")
                    }
                } label: {
                    Label("Tools", systemImage: mode == .draw ? "pencil.tip" : "textformat")
                }

                Button {
                    showTemplateSheet = true
                } label: {
                    Label("Page Template", systemImage: "doc.plaintext")
                }

                Menu {
                    Button {
                        addPage()
                    } label: {
                        Label("Add Page", systemImage: "plus.rectangle")
                    }
                    Button(role: .destructive) {
                        deleteCurrentPage()
                    } label: {
                        Label("Delete Page", systemImage: "trash")
                    }
                    .disabled(sortedPages.count <= 1)
                    Button {
                        showThumbnails.toggle()
                    } label: {
                        Label(showThumbnails ? "Hide Pages" : "Show Pages", systemImage: "square.grid.2x2")
                    }
                    if let page = currentPage {
                        ShareLink(
                            item: Image(uiImage: page.renderedImage()),
                            preview: SharePreview("\(notebook.title) page", image: Image(uiImage: page.renderedImage()))
                        ) {
                            Label("Export Page as Image", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Label("Page", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showTemplateSheet) {
            if let page = currentPage {
                NavigationStack {
                    Form {
                        Section("Paper Template for This Page") {
                            TemplatePicker(selection: Binding(
                                get: { page.template },
                                set: { page.template = $0 }
                            ))
                        }
                    }
                    .navigationTitle("Page Template")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showTemplateSheet = false }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAIAssistant) {
            AIAssistantSheet(page: currentPage)
        }
        .onAppear {
            if currentPageID == nil {
                currentPageID = sortedPages.first?.persistentModelID
            }
            if let page = currentPage {
                loadPage(page)
            }
        }
    }

    private func loadPage(_ page: Page) {
        currentPageID = page.persistentModelID
        drawing = (try? PKDrawing(data: page.drawingData)) ?? PKDrawing()
    }

    private func persist(drawing newDrawing: PKDrawing) {
        guard let page = currentPage else { return }
        page.drawingData = newDrawing.dataRepresentation()
        page.updatedAt = .now
        notebook.updatedAt = .now
    }

    private func addPage() {
        let newPage = Page(index: sortedPages.count, template: notebook.defaultTemplate, notebook: notebook)
        modelContext.insert(newPage)
        notebook.updatedAt = .now
        loadPage(newPage)
    }

    private func deleteCurrentPage() {
        guard let page = currentPage, sortedPages.count > 1 else { return }
        let remaining = sortedPages.filter { $0.persistentModelID != page.persistentModelID }
        modelContext.delete(page)
        for (newIndex, remainingPage) in remaining.enumerated() {
            remainingPage.index = newIndex
        }
        if let next = remaining.first {
            loadPage(next)
        }
    }
}

extension Page {
    func renderedImage() -> UIImage {
        let drawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        let bounds = CGRect(origin: .zero, size: PageSize.standard)
        let renderer = UIGraphicsImageRenderer(size: PageSize.standard)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(bounds)
            let inkImage = drawing.image(from: bounds, scale: 2)
            inkImage.draw(in: bounds)
        }
    }
}

struct TemplateBackgroundView: View {
    let template: PageTemplate

    var body: some View {
        Canvas { context, size in
            template.draw(in: context, size: size)
        }
    }
}
