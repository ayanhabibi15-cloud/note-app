import SwiftUI
import SwiftData

@main
struct InkwellApp: App {
    /// Built once here rather than with the `.modelContainer(for:)` convenience
    /// so a schema mistake surfaces as a readable crash instead of a silent
    /// empty database.
    private let container: ModelContainer = {
        do {
            return try ModelContainer(for: Schema(InkwellSchema.models))
        } catch {
            fatalError("Couldn't create the Inkwell data store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
        .commands {
            // Mac and iPad keyboard users expect ⌘N to make something. The
            // sidebar owns folder creation, so this mirrors it at the menu bar.
            SidebarCommands()
        }
    }
}
