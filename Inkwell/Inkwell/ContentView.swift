import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedFolder: Folder?
    @State private var showAllNotebooks = true

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedFolder: $selectedFolder, showAllNotebooks: $showAllNotebooks)
        } detail: {
            NavigationStack {
                NotebookGridView(folder: selectedFolder, showingAll: showAllNotebooks)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Folder.self, Notebook.self, Page.self], inMemory: true)
}
