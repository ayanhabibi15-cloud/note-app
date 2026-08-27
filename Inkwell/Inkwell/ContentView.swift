import SwiftUI
import SwiftData

/// The sections of the app, used as the sidebar's selection value.
///
/// Folders get their own case (carrying a `PersistentIdentifier` rather than
/// the model, so the enum stays `Hashable` and cheap) which is what lets the
/// notebook folder tree live in the same sidebar as everything else.
enum AppSection: Hashable {
    case today
    case tasks
    case documents
    case assistant
    case allNotebooks
    case folder(PersistentIdentifier)
}

/// Root view: one sidebar holding every part of the app, and a detail column
/// that swaps between them. On iPad and the Mac this reads as a single
/// workspace rather than five apps stitched together; on iPhone the split view
/// collapses to a push navigation automatically.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var selection: AppSection? = .today
    @State private var showSettings = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            AppSidebar(selection: $selection, showSettings: $showSettings)
        } detail: {
            NavigationStack {
                detail
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .today, nil:
            TodayView()
        case .tasks:
            TasksView()
        case .documents:
            DocumentsView()
        case .assistant:
            AssistantView()
        case .allNotebooks:
            NotebookGridView(folder: nil, showingAll: true)
        case .folder(let id):
            if let folder = modelContext.model(for: id) as? Folder {
                NotebookGridView(folder: folder, showingAll: false)
            } else {
                ContentUnavailableView("Folder Not Found", systemImage: "folder.badge.questionmark")
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: InkwellSchema.models, inMemory: true)
}
