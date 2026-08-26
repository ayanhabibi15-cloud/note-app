import SwiftUI
import SwiftData

struct SidebarView: View {
    @Query(filter: #Predicate<Folder> { $0.parent == nil }, sort: \Folder.sortOrder)
    private var rootFolders: [Folder]

    @Environment(\.modelContext) private var modelContext

    @Binding var selectedFolder: Folder?
    @Binding var showAllNotebooks: Bool
    @State private var showSettings = false
    @State private var isAddingFolder = false
    @State private var newFolderName = ""

    var body: some View {
        List {
            Section {
                Button {
                    selectedFolder = nil
                    showAllNotebooks = true
                } label: {
                    Label("All Notebooks", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.plain)
            }

            Section("Folders") {
                ForEach(rootFolders) { folder in
                    FolderRow(folder: folder, selectedFolder: $selectedFolder, showAllNotebooks: $showAllNotebooks)
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
                guard !newFolderName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                let folder = Folder(name: newFolderName, sortOrder: rootFolders.count)
                modelContext.insert(folder)
                newFolderName = ""
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

private struct FolderRow: View {
    @Bindable var folder: Folder
    @Binding var selectedFolder: Folder?
    @Binding var showAllNotebooks: Bool
    @Environment(\.modelContext) private var modelContext
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isAddingSubfolder = false
    @State private var newSubfolderName = ""

    var body: some View {
        if folder.subfolders.isEmpty {
            row
        } else {
            DisclosureGroup {
                ForEach(folder.subfolders) { sub in
                    FolderRow(folder: sub, selectedFolder: $selectedFolder, showAllNotebooks: $showAllNotebooks)
                }
            } label: {
                row
            }
        }
    }

    private var row: some View {
        Button {
            selectedFolder = folder
            showAllNotebooks = false
        } label: {
            Label {
                Text(folder.name)
            } icon: {
                Image(systemName: folder.symbolName)
                    .foregroundStyle(ColorPalette.color(named: folder.colorName))
            }
        }
        .buttonStyle(.plain)
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
                    Button {
                        folder.colorName = palette.rawValue
                    } label: {
                        Label(palette.rawValue.capitalized, systemImage: "circle.fill")
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
                guard !renameText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                folder.name = renameText
            }
        }
        .alert("New Subfolder", isPresented: $isAddingSubfolder) {
            TextField("Folder name", text: $newSubfolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                guard !newSubfolderName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                let sub = Folder(name: newSubfolderName, parent: folder, sortOrder: folder.subfolders.count)
                modelContext.insert(sub)
            }
        }
    }
}
