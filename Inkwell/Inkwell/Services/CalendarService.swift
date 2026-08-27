import Foundation
import EventKit

/// A calendar event or reminder, flattened into the shape the briefing needs.
struct AgendaEntry: Identifiable, Hashable {
    enum Source: String {
        case calendar
        case reminder
    }

    let id: String
    let title: String
    let start: Date?
    let end: Date?
    let isAllDay: Bool
    let location: String?
    let calendarName: String
    let source: Source

    var timeDescription: String {
        guard let start else { return "No time set" }
        if isAllDay { return "All day" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let startText = formatter.string(from: start)
        guard let end, end > start else { return startText }
        return "\(startText) – \(formatter.string(from: end))"
    }
}

/// Reads today's events and reminders from Apple Calendar and Reminders.
///
/// This is the one place the app touches system data, and it's read-only: the
/// briefing pulls what's already on the user's calendar rather than asking
/// them to re-enter it here. Access is requested lazily — the app works fine
/// if permission is refused, the briefing just says the calendar is unavailable.
final class CalendarService {
    /// One shared store: `EKEventStore` is expensive to create and, more
    /// importantly, permission prompts are tied to the instance that asked.
    static let shared = CalendarService()

    private let store = EKEventStore()

    private init() {}

    /// Read live each time rather than cached: the user can flip these in
    /// Settings while the app is backgrounded, and a stale cached value would
    /// silently produce an empty briefing.
    var isCalendarAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    var isReminderAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    @discardableResult
    func requestCalendarAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    @discardableResult
    func requestReminderAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    /// Events between the start of `date` and the start of the following day.
    func events(on date: Date = .now) -> [AgendaEntry] {
        guard isCalendarAuthorized else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { ($0.startDate ?? start) < ($1.startDate ?? start) }
            .map { event in
                AgendaEntry(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Untitled event",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    location: event.location,
                    calendarName: event.calendar?.title ?? "Calendar",
                    source: .calendar
                )
            }
    }

    /// Incomplete reminders due on or before the end of `date`, so anything
    /// overdue in Apple Reminders still shows up in the morning briefing.
    func reminders(dueBy date: Date = .now) async -> [AgendaEntry] {
        guard isReminderAuthorized else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: end,
            calendars: nil
        )

        let fetched: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }

        return fetched.map { reminder in
            let due = reminder.dueDateComponents.flatMap { calendar.date(from: $0) }
            return AgendaEntry(
                id: reminder.calendarItemIdentifier,
                title: reminder.title ?? "Untitled reminder",
                start: due,
                end: nil,
                isAllDay: reminder.dueDateComponents?.hour == nil,
                location: nil,
                calendarName: reminder.calendar?.title ?? "Reminders",
                source: .reminder
            )
        }
        .sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }
}
