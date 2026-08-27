import Foundation
import SwiftData

/// Assembles the plain-text picture of the user's workspace that gets sent to
/// Claude alongside a question.
///
/// This is deliberately explicit rather than clever: everything the model sees
/// is built here, in one readable function per section, so it's always possible
/// to answer "what exactly did it get told about me?" — the assistant screen
/// shows the same summary back to the user before each send.
struct WorkspaceContext {

    /// Per-document budget when a document is included in a prompt. Full
    /// extracted text can run to tens of thousands of characters; a whole
    /// library of those would be both slow and expensive.
    static let perDocumentCharacterBudget = 12_000

    struct Options {
        var areas: Set<LifeArea> = Set(LifeArea.allCases)
        var includeTasks = true
        var includeDocuments = true
        var includeNotebooks = true
        var includeAgenda = true
        /// Documents the user explicitly attached to this question. These are
        /// included in full (up to the budget) even if they're outside `areas`.
        var attachedDocumentIDs: Set<PersistentIdentifier> = []
    }

    struct Assembled {
        var text: String
        /// One-line description of what went in, shown under the message.
        var summary: String
    }

    // MARK: - Sections

    static func tasksSection(_ tasks: [TaskItem], areas: Set<LifeArea>) -> String {
        let relevant = tasks.filter { areas.contains($0.area) }
        let open = relevant.filter { !$0.isDone }
        guard !open.isEmpty else { return "TASKS: none open." }

        let overdue = open.filter(\.isOverdue)
        let today = open.filter { $0.isDueToday && !$0.isOverdue }
        let upcoming = open.filter { task in
            guard let due = task.dueDate else { return false }
            return !task.isOverdue && !task.isDueToday && due < Date.now.addingTimeInterval(7 * 86_400)
        }
        let someday = open.filter { $0.dueDate == nil }

        var lines = ["TASKS"]
        appendGroup("Overdue", overdue, to: &lines)
        appendGroup("Due today", today, to: &lines)
        appendGroup("Next 7 days", upcoming, to: &lines)
        appendGroup("No due date", Array(someday.prefix(15)), to: &lines)
        return lines.joined(separator: "\n")
    }

    private static func appendGroup(_ name: String, _ tasks: [TaskItem], to lines: inout [String]) {
        guard !tasks.isEmpty else { return }
        lines.append("  \(name):")
        for task in tasks.sorted(by: taskOrder) {
            lines.append("    - \(describe(task))")
        }
    }

    private static func taskOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.priority.rawValue != rhs.priority.rawValue {
            return lhs.priority.rawValue > rhs.priority.rawValue
        }
        return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
    }

    private static func describe(_ task: TaskItem) -> String {
        var parts = ["[\(task.area.title)] \(task.title)"]
        if !task.course.isEmpty { parts.append("(\(task.course))") }
        if let due = task.dueDate {
            parts.append("due \(format(due, withTime: task.hasDueTime))")
        }
        if task.priority != .none { parts.append("priority \(task.priority.title.lowercased())") }
        if !task.details.isEmpty { parts.append("— \(collapse(task.details, limit: 200))") }
        let openSubtasks = task.subtasks.filter { !$0.isDone }
        if !openSubtasks.isEmpty {
            parts.append("subtasks: " + openSubtasks.map(\.title).joined(separator: "; "))
        }
        return parts.joined(separator: " ")
    }

    static func notebooksSection(_ notebooks: [Notebook], areas: Set<LifeArea>) -> String {
        let relevant = notebooks.filter { areas.contains($0.area) }
        guard !relevant.isEmpty else { return "NOTEBOOKS: none." }
        var lines = ["NOTEBOOKS (handwritten; ask the user to open one for its contents)"]
        for notebook in relevant.sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(25) {
            let folderName = notebook.folder?.name ?? "No folder"
            lines.append("  - [\(notebook.area.title)] \(notebook.title) · \(folderName) · \(notebook.pages.count) pages · updated \(format(notebook.updatedAt, withTime: false))")
        }
        return lines.joined(separator: "\n")
    }

    static func documentsSection(
        _ documents: [StoredDocument],
        areas: Set<LifeArea>,
        attachedIDs: Set<PersistentIdentifier>
    ) -> String {
        guard !documents.isEmpty else { return "DOCUMENTS: none filed." }

        let included = documents.filter { document in
            attachedIDs.contains(document.persistentModelID)
                || (document.isPinnedToAssistant && areas.contains(document.area))
        }
        let listedOnly = documents.filter { document in
            !included.contains { $0.persistentModelID == document.persistentModelID }
                && areas.contains(document.area)
        }

        var lines: [String] = []

        if !listedOnly.isEmpty {
            lines.append("DOCUMENTS AVAILABLE (contents not included — the user can attach one to share it)")
            for document in listedOnly.sorted(by: { $0.addedAt > $1.addedAt }).prefix(40) {
                var descriptor = "  - [\(document.area.title)] \(document.title)"
                if !document.course.isEmpty { descriptor += " (\(document.course))" }
                descriptor += " · \(document.originalFilename) · \(document.formattedSize)"
                if !document.hasText { descriptor += " · no readable text" }
                lines.append(descriptor)
            }
        }

        for document in included where document.hasText {
            lines.append("")
            lines.append("DOCUMENT: \(document.title) (\(document.originalFilename), \(document.area.title))")
            if !document.notes.isEmpty { lines.append("User's note on this document: \(document.notes)") }
            lines.append("---")
            lines.append(clip(document.extractedText, to: perDocumentCharacterBudget))
            lines.append("--- end of \(document.title) ---")
        }

        return lines.isEmpty ? "DOCUMENTS: none in scope." : lines.joined(separator: "\n")
    }

    static func agendaSection(events: [AgendaEntry], reminders: [AgendaEntry]) -> String {
        var lines: [String] = []
        if events.isEmpty {
            lines.append("CALENDAR TODAY: nothing scheduled (or calendar access is off).")
        } else {
            lines.append("CALENDAR TODAY")
            for event in events {
                var descriptor = "  - \(event.timeDescription): \(event.title)"
                if let location = event.location, !location.isEmpty { descriptor += " @ \(location)" }
                descriptor += " · \(event.calendarName)"
                lines.append(descriptor)
            }
        }
        if !reminders.isEmpty {
            lines.append("APPLE REMINDERS DUE")
            for reminder in reminders.prefix(20) {
                var descriptor = "  - \(reminder.title)"
                if let due = reminder.start {
                    descriptor += " · due " + format(due, withTime: !due.isMidnight)
                }
                lines.append(descriptor)
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Assembly

    static func assemble(
        options: Options,
        tasks: [TaskItem],
        notebooks: [Notebook],
        documents: [StoredDocument],
        events: [AgendaEntry],
        reminders: [AgendaEntry]
    ) -> Assembled {
        var blocks: [String] = [header(areas: options.areas)]
        var summaryParts: [String] = []

        if options.includeAgenda {
            blocks.append(agendaSection(events: events, reminders: reminders))
            if !events.isEmpty { summaryParts.append("\(events.count) event\(events.count == 1 ? "" : "s")") }
        }

        if options.includeTasks {
            blocks.append(tasksSection(tasks, areas: options.areas))
            let openCount = tasks.filter { !$0.isDone && options.areas.contains($0.area) }.count
            if openCount > 0 { summaryParts.append("\(openCount) open task\(openCount == 1 ? "" : "s")") }
        }

        if options.includeNotebooks {
            blocks.append(notebooksSection(notebooks, areas: options.areas))
        }

        if options.includeDocuments {
            blocks.append(documentsSection(documents, areas: options.areas, attachedIDs: options.attachedDocumentIDs))
            let sharedCount = documents.filter {
                options.attachedDocumentIDs.contains($0.persistentModelID)
                    || ($0.isPinnedToAssistant && options.areas.contains($0.area))
            }.count
            if sharedCount > 0 { summaryParts.append("\(sharedCount) document\(sharedCount == 1 ? "" : "s")") }
        }

        let text = blocks.filter { !$0.isEmpty }.joined(separator: "\n\n")
        let summary = summaryParts.isEmpty ? "No workspace context attached" : "Shared: " + summaryParts.joined(separator: ", ")
        return Assembled(text: text, summary: summary)
    }

    private static func header(areas: Set<LifeArea>) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        let areaList = LifeArea.allCases
            .filter { areas.contains($0) }
            .map(\.title)
            .joined(separator: ", ")
        return """
        CURRENT TIME: \(formatter.string(from: .now))
        AREAS IN SCOPE: \(areaList.isEmpty ? "none" : areaList)
        """
    }

    // MARK: - Formatting helpers

    static func format(_ date: Date, withTime: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = withTime ? .short : .none
        if Calendar.current.isDateInToday(date) {
            return withTime ? "today \(shortTime(date))" : "today"
        }
        if Calendar.current.isDateInTomorrow(date) {
            return withTime ? "tomorrow \(shortTime(date))" : "tomorrow"
        }
        return formatter.string(from: date)
    }

    private static func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func collapse(_ text: String, limit: Int) -> String {
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clip(flattened, to: limit)
    }

    private static func clip(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }
}

extension Date {
    /// True when the date lands exactly on midnight, which is how an all-day
    /// reminder's due date comes back from EventKit.
    var isMidnight: Bool {
        let components = Calendar.current.dateComponents([.hour, .minute], from: self)
        return components.hour == 0 && components.minute == 0
    }
}
