import SwiftUI
import SwiftData

@main
struct InkwellApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Folder.self, Notebook.self, Page.self])
    }
}
