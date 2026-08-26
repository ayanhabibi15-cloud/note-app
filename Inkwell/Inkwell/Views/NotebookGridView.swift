import SwiftUI
import SwiftData

struct NotebookGridView: View {
    var folder: Folder?
    var showingAll: Bool

    @Environment(\.modelContext) private var modelContext
    @Query private var allNotebooks: [Notebook]

    @State private var isCreatingNotebook = false

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 20)]

    init(folder: Folder?, showingAll: Bool) {
        self.folder = folder
        self.showingAll = showingAll
        _allNotebooks = Query(sort: \Notebook.updatedAt, order: .reverse)
    }

    private var notebooks: [Notebook] {
        if showingAll {
            return allNotebooks
        }
        guard let folder else { return [] }
        return allNotebooks.filter { $0.folder?.persistentModelID == folder.persistentModelID }
    }

    var body: some View {
        ScrollView {
            if notebooks.isEmpty {
                ContentUnavailableView(
                    "No Notebooks Yet",
                    systemImage: "book.closed",
                    description: Text("Tap + to create your first notebook here.")
                )
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(notebooks) { notebook in
                        NavigationLink(value: notebook) {
                            NotebookCoverView(notebook: notebook)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                modelContext.delete(notebook)
                            } label: {
                                Label("Delete Notebook", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(showingAll ? "All Notebooks" : (folder?.name ?? "Notebooks"))
        .navigationDestination(for: Notebook.self) { notebook in
            PageEditorView(notebook: notebook)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreatingNotebook = true
                } label: {
                    Label("New Notebook", systemImage: "plus")
                }
                .disabled(!showingAll && folder == nil)
            }
        }
        .sheet(isPresented: $isCreatingNotebook) {
            NewNotebookSheet(folder: folder) { title, template, color in
                let notebook = Notebook(title: title, template: template, coverColorName: color.rawValue, folder: folder)
                modelContext.insert(notebook)
                let firstPage = Page(index: 0, template: template, notebook: notebook)
                modelContext.insert(firstPage)
            }
        }
    }
}

struct NotebookCoverView: View {
    let notebook: Notebook

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 10)
                .fill(ColorPalette.color(named: notebook.coverColorName).gradient)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    Image(systemName: notebook.defaultTemplate.symbolName)
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(12)
                }
                .overlay(alignment: .bottomLeading) {
                    Text("\(notebook.pages.count) page\(notebook.pages.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(10)
                }
                .shadow(radius: 3, y: 2)

            Text(notebook.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}

private struct NewNotebookSheet: View {
    let folder: Folder?
    let onCreate: (String, PageTemplate, ColorPalette) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var template: PageTemplate = .linedWide
    @State private var color: ColorPalette = .yellow

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Notebook title", text: $title)
                }
                Section("Cover Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(ColorPalette.allCases) { palette in
                            Circle()
                                .fill(palette.color)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if palette == color {
                                        Circle().stroke(.primary, lineWidth: 2)
                                    }
                                }
                                .onTapGesture { color = palette }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Paper Template") {
                    TemplatePicker(selection: $template)
                }
            }
            .navigationTitle("New Notebook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let name = title.trimmingCharacters(in: .whitespaces)
                        onCreate(name.isEmpty ? "Untitled" : name, template, color)
                        dismiss()
                    }
                }
            }
        }
    }
}
