import Foundation
import SwiftData

/// One message in an assistant conversation. `role` is stored as the raw
/// string the Anthropic Messages API expects ("user" / "assistant") so
/// building a request is a straight map with no translation step.
@Model
final class ChatMessage {
    var role: String
    var text: String
    var createdAt: Date
    /// Short human-readable summary of what was attached to this turn
    /// ("3 tasks, Bio syllabus"), shown under the bubble so it's always clear
    /// what left the device.
    var contextSummary: String

    var thread: ChatThread?

    init(role: String, text: String, contextSummary: String = "", thread: ChatThread? = nil) {
        self.role = role
        self.text = text
        self.createdAt = .now
        self.contextSummary = contextSummary
        self.thread = thread
    }

    var isUser: Bool { role == "user" }
}

/// A saved assistant conversation. Threads persist so a long back-and-forth
/// about an essay or a project plan survives closing the app.
@Model
final class ChatThread {
    var title: String
    var createdAt: Date
    var updatedAt: Date
    /// Areas whose tasks and documents are offered to the model in this thread.
    /// Stored as a comma-joined list of `LifeArea` raw values.
    var scopeRawValue: String

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.thread)
    var messages: [ChatMessage] = []

    var scope: Set<LifeArea> {
        get {
            let parts = scopeRawValue.split(separator: ",").map(String.init)
            return Set(parts.compactMap(LifeArea.init(rawValue:)))
        }
        set {
            scopeRawValue = newValue.map(\.rawValue).sorted().joined(separator: ",")
        }
    }

    init(title: String = "New Conversation", scope: Set<LifeArea> = Set(LifeArea.allCases)) {
        self.title = title
        self.createdAt = .now
        self.updatedAt = .now
        self.scopeRawValue = scope.map(\.rawValue).sorted().joined(separator: ",")
    }

    var sortedMessages: [ChatMessage] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }
}
