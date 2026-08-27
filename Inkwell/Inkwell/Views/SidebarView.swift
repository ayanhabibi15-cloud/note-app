import SwiftUI
import SwiftData

/// The one sidebar for the whole app: the daily views on top, the notebook
/// folder tree below. Keeping folders in the same list as Today and Tasks is
/// what makes this feel like one workspace — you can drop from "what's due"
/// straight into the notebook for that class without changing apps.
struct AppSidebar: View {
    @Query(filter: #Predicate<Folder> { $0.parent == nil }, sort: \Folder.sortOrder)
    private var rootFolders: [Folder]

    // Written as `== false` rather than `!`: SwiftData's predicate builder
    // handles the explicit comparison more reliably than the negation operator.
    @Query(filter: #Predicate<TaskItem> { $0.isDone == false })
    private var openTasks: [TaskItem]

    @Environment(\.modelContext) private var modelContext

    @Binding var selection: AppSection?
    @Binding var showSettings: Bool

    @State private var isAddingFolder = false
    @State private var newFolderName = ""

    private var dueTodayCount: Int {
        openTasks.filter { $0.isDueToday || $0.isOverdue }.count
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Today", systemImage: "sun.horizon.fill")
                    .tag(AppSection.today)

                Label("Tasks", systemImage: "checklist")
                    .badge(dueTodayCount)
                    .tag(AppSection.tasks)

                Label("Documents", systemImage: "folder.fill.badge.person.crop")
                    .tag(AppSection.documents)

                Label("Assistant", systemImage: "sparkles")
                    .tag(AppSection.assistant)
            }

            Section("Notes") {
                Label("All Notebooks", systemImage: "square.grid.2x2")
                    .tag(AppSection.allNotebooks)

                ForEach(rootFolders) { folder in
                    FolderRow(folder: folder)
                }
                .onDelete { indexSet in
                    for index in indexSet { modelContext.delete(rootFolders[index]) }
                }
            }
        }
        .navigationTitle("Inkwell")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .alert("New Folder", isPresented: $isAddingFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") {
                let name = newFolderName.trimmingCharacters(in: .whitespaces)
                newFolderName = ""
                guard !name.isEmpty else { return }
                modelContext.insert(Folder(name: name, sortOrder: rootFolders.count))
            }
        }
    }
}

/// One folder in the tree, recursing into its subfolders. Uses `.tag` so the
/// row participates in the enclosing `List`'s selection rather than pushing a
/// separate navigation destination.
private struct FolderRow: View {
    @Bindable var folder: Folder
    @Environment(\.modelContext) private var modelContext

    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isAddingSubfolder = false
    @State private var newSubfolderName = ""

    var body: some View {
        Group {
            if folder.subfolders.isEmpty {
                label
            } else {
                DisclosureGroup {
                    ForEach(folder.subfolders) { sub in
                        FolderRow(folder: sub)
                    }
                } label: {
                    label
                }
            }
        }
        .contextMenu {
            Button {
                renameText = folder.name
                isRenaming = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                newSubfolderName = ""
                isAddingSubfolder = true
            } label: {
                Label("New Subfolder", systemImage: "folder.badge.plus")
            }
            Menu("Color") {
                ForEach(ColorPalette.allCases) { palette in
                    Button(palette.rawValue.capitalized) {
                        folder.colorName = palette.rawValue
                    }
                }
            }
            Button(role: .destructive) {
                modelContext.delete(folder)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Rename Folder", isPresented: $isRenaming) {
            TextField("Folder name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                folder.name = name
            }
        }
        .alert("New Subfolder", isPresented: $isAddingSubfolder) {
            TextField("Folder name", text: $newSubfolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newSubfolderName.trimmingCharacters(in: .whitespaces)
                newSubfolderName = ""
                guard !name.isEmpty else { return }
                modelContext.insert(Folder(name: name, parent: folder, sortOrder: folder.subfolders.count))
            }
        }
    }

    private var label: some View {
        Label {
            Text(folder.name)
        } icon: {
            Image(systemName: folder.symbolName)
                .foregroundStyle(ColorPalette.color(named: folder.colorName))
        }
        .tag(AppSection.folder(folder.persistentModelID))
    }
}
