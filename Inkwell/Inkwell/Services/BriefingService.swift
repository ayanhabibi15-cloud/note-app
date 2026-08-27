import Foundation
import SwiftData

/// Builds the morning briefing.
///
/// The briefing has two layers. The **facts** layer is assembled entirely on
/// device from today's calendar, Apple Reminders, and the app's own tasks — it
/// works with no network and no API key, and it's what the Today screen falls
/// back to. The **narrative** layer asks Claude to turn those facts into a
/// short read-it-in-thirty-seconds plan for the day, and is cached per calendar
/// day so opening the app ten times doesn't cost ten API calls.
struct BriefingService {

    struct Facts {
        var events: [AgendaEntry]
        var reminders: [AgendaEntry]
        var overdue: [TaskItem]
        var dueToday: [TaskItem]
        var dueSoon: [TaskItem]
        var summaryText: String

        var isQuietDay: Bool {
            events.isEmpty && reminders.isEmpty && overdue.isEmpty && dueToday.isEmpty
        }
    }

    /// Gathers everything today needs, with no network involved.
    static func gatherFacts(tasks: [TaskItem], date: Date = .now) async -> Facts {
        let calendar = CalendarService.shared
        let events = calendar.events(on: date)
        let reminders = await calendar.reminders(dueBy: date)

        let open = tasks.filter { !$0.isDone }
        let overdue = open.filter(\.isOverdue).sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
        let dueToday = open.filter { $0.isDueToday && !$0.isOverdue }
        let horizon = Calendar.current.date(byAdding: .day, value: 3, to: date) ?? date
        let dueSoon = open.filter { task in
            guard let due = task.dueDate else { return false }
            return !task.isOverdue && !task.isDueToday && due <= horizon
        }
        .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

        let summary = factsText(
            date: date,
            events: events,
            reminders: reminders,
            overdue: overdue,
            dueToday: dueToday,
            dueSoon: dueSoon
        )

        return Facts(
            events: events,
            reminders: reminders,
            overdue: overdue,
            dueToday: dueToday,
            dueSoon: dueSoon,
            summaryText: summary
        )
    }

    /// The exact text handed to the model — also shown in the UI under
    /// "What Claude was told", so the briefing is never a black box.
    static func factsText(
        date: Date,
        events: [AgendaEntry],
        reminders: [AgendaEntry],
        overdue: [TaskItem],
        dueToday: [TaskItem],
        dueSoon: [TaskItem]
    ) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.dateStyle = .full

        var lines = ["DATE: \(dayFormatter.string(from: date))"]

        lines.append("")
        lines.append(WorkspaceContext.agendaSection(events: events, reminders: reminders))

        func section(_ title: String, _ items: [TaskItem]) {
            lines.append("")
            if items.isEmpty {
                lines.append("\(title): none")
                return
            }
            lines.append(title)
            for task in items.prefix(20) {
                var descriptor = "  - [\(task.area.title)] \(task.title)"
                if !task.course.isEmpty { descriptor += " (\(task.course))" }
                if let due = task.dueDate {
                    descriptor += " · due " + WorkspaceContext.format(due, withTime: task.hasDueTime)
                }
                if task.priority != .none { descriptor += " · \(task.priority.title.lowercased()) priority" }
                lines.append(descriptor)
            }
        }

        section("OVERDUE TASKS", overdue)
        section("TASKS DUE TODAY", dueToday)
        section("TASKS DUE IN THE NEXT 3 DAYS", dueSoon)

        return lines.joined(separator: "\n")
    }

    private static let systemPrompt = """
    You write a short morning briefing for one person — a student who is also \
    juggling home responsibilities, extracurricular activities, and outside \
    projects. You are given only the facts below: their calendar for today, \
    their Apple Reminders, and their open tasks grouped by urgency.

    Write the briefing as if you were a sharp, unfussy chief of staff:

    - Open with one sentence on the shape of the day (how busy, what dominates).
    - Then a short prioritized plan: what to do first, and what can wait. Be \
      specific and reference actual task and event names.
    - Call out genuine collisions — an event that overlaps another, a deadline \
      that can't survive the day's schedule — but only real ones.
    - If something is overdue, say so plainly once. Don't scold.
    - Close with one line on what would make today a win.

    Rules: use only the facts given; never invent a meeting, deadline, or \
    commitment. Keep it under 250 words. Use Markdown with short paragraphs \
    and at most one bulleted list. Write in second person. No greeting preamble \
    like "Good morning!" — start with the substance. If the day is genuinely \
    empty, say so in two sentences and suggest one useful thing from their \
    task list rather than padding.
    """

    /// Asks Claude to turn the facts into a narrative. Throws
    /// `ClaudeAPIError.missingAPIKey` when no key is configured, which callers
    /// treat as "show the facts alone" rather than as an error worth surfacing.
    static func generateNarrative(
        facts: Facts,
        model: ClaudeModel,
        apiKey: String
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw ClaudeAPIError.missingAPIKey }
        let service = ClaudeAPIService()
        return try await service.send(
            messages: [.user(facts.summaryText)],
            system: systemPrompt,
            model: model,
            maxTokens: 900,
            apiKey: apiKey
        )
    }
}
