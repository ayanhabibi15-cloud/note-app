import Foundation
import SwiftData

/// The full list of persisted models, in one place so the app, the previews,
/// and any future CloudKit container all stay in sync. Forgetting to add a new
/// `@Model` here is the classic SwiftData crash-on-launch, so nothing else in
/// the app should hardcode a partial list.
enum InkwellSchema {
    static let models: [any PersistentModel.Type] = [
        Folder.self,
        Notebook.self,
        Page.self,
        TaskItem.self,
        StoredDocument.self,
        ChatThread.self,
        ChatMessage.self,
        DailyBriefing.self
    ]
}
