import Foundation
import SwiftData

/// Priority levels, ordered so `sortRank` can drive list ordering directly.
enum TaskPriority: Int, CaseIterable, Identifiable, Codable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// `!` flags, the way Reminders shows priority. Empty for `.none`.
    var flagText: String {
        switch self {
        case .none: return ""
        case .low: return "!"
        case .medium: return "!!"
        case .high: return "!!!"
        }
    }
}

/// How a task repeats after it's checked off. Completing a repeating task
/// rolls its due date forward instead of archiving it, which is what makes
/// recurring chores and weekly practice sessions bearable to track.
enum TaskRecurrence: String, CaseIterable, Identifiable, Codable {
    case none
    case daily
    case weekdays
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Never"
        case .daily: return "Every day"
        case .weekdays: return "Every weekday"
        case .weekly: return "Every week"
        case .monthly: return "Every month"
        }
    }

    /// The next due date after `date`, or `nil` when the task doesn't repeat.
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .none:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekdays:
            var candidate = date
            repeat {
                guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
                candidate = next
            } while calendar.isDateInWeekend(candidate)
            return candidate
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        }
    }
}

/// A checklist item nested inside a task. Stored as JSON on `TaskItem` rather
/// than as its own `@Model`, the same trick `Page` uses for text boxes: these
/// are only ever read and written together with their parent.
struct Subtask: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false
}

/// One to-do. Tasks carry a `LifeArea` so school work, chores, club
/// commitments, and side projects can live in one list but still be filtered
/// apart, and an optional `course` tag for the finer grouping within an area
/// (a class name, a club, a client).
@Model
final class TaskItem {
    var title: String
    var details: String
    var areaRawValue: String
    var course: String
    var priorityRawValue: Int
    var recurrenceRawValue: String
    var dueDate: Date?
    /// When true, `dueDate` means "this exact time"; when false it means
    /// "sometime that day" and the UI hides the clock.
    var hasDueTime: Bool
    var isDone: Bool
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var subtasksData: Data

    /// Optional link back to a notebook, so "study for the bio test" can open
    /// the bio notebook directly.
    var notebook: Notebook?

    var area: LifeArea {
        get { LifeArea.from(areaRawValue) }
        set { areaRawValue = newValue.rawValue }
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRawValue) ?? .none }
        set { priorityRawValue = newValue.rawValue }
    }

    var recurrence: TaskRecurrence {
        get { TaskRecurrence(rawValue: recurrenceRawValue) ?? .none }
        set { recurrenceRawValue = newValue.rawValue }
    }

    var subtasks: [Subtask] {
        get { (try? JSONDecoder().decode([Subtask].self, from: subtasksData)) ?? [] }
        set { subtasksData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(
        title: String,
        details: String = "",
        area: LifeArea = .personal,
        course: String = "",
        priority: TaskPriority = .none,
        recurrence: TaskRecurrence = .none,
        dueDate: Date? = nil,
        hasDueTime: Bool = false,
        notebook: Notebook? = nil
    ) {
        self.title = title
        self.details = details
        self.areaRawValue = area.rawValue
        self.course = course
        self.priorityRawValue = priority.rawValue
        self.recurrenceRawValue = recurrence.rawValue
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.isDone = false
        self.completedAt = nil
        self.createdAt = .now
        self.updatedAt = .now
        self.subtasksData = Data()
        self.notebook = notebook
    }

    var isOverdue: Bool {
        guard !isDone, let dueDate else { return false }
        if hasDueTime { return dueDate < .now }
        return dueDate < Calendar.current.startOfDay(for: .now)
    }

    var isDueToday: Bool {
        guard let dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    /// Checks a task off. Repeating tasks roll forward to their next due date
    /// and stay open, with their subtasks reset, rather than disappearing.
    func complete(on date: Date = .now) {
        if recurrence != .none, let dueDate, let next = recurrence.nextDate(after: dueDate) {
            self.dueDate = next
            subtasks = subtasks.map { var copy = $0; copy.isDone = false; return copy }
            isDone = false
            completedAt = nil
        } else {
            isDone = true
            completedAt = date
        }
        updatedAt = .now
    }

    func reopen() {
        isDone = false
        completedAt = nil
        updatedAt = .now
    }
}
