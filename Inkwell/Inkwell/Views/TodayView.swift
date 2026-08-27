import SwiftUI
import SwiftData
import UIKit

/// The morning briefing.
///
/// Opens on facts assembled entirely on device — today's calendar, Apple
/// Reminders, and what's due — so the screen is useful the instant it appears
/// and stays useful with no API key and no signal. Claude's written plan sits
/// on top of that, generated once per day and cached.
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var tasks: [TaskItem]
    @Query private var briefings: [DailyBriefing]

    @AppStorage("claudeModel") private var modelRawValue = ClaudeModel.sonnet.rawValue
    @AppStorage("autoGenerateBriefing") private var autoGenerate = true

    @State private var facts: BriefingService.Facts?
    @State private var calendarAuthorized = false
    @State private var remindersAuthorized = false
    @State private var isLoadingFacts = true
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showFactsSheet = false

    private var model: ClaudeModel { ClaudeModel(rawValue: modelRawValue) ?? .sonnet }
    private var todayKey: String { DailyBriefing.dayKey() }
    private var todaysBriefing: DailyBriefing? { briefings.first { $0.dayKey == todayKey } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                greeting

                if isLoadingFacts {
                    ProgressView("Gathering your day…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if let facts {
                    narrativeCard
                    calendarCard(facts: facts)
                    taskCards(facts: facts)
                    accessPrompts
                }
            }
            .padding(24)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Today")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Task { await generate(force: true) }
                    } label: {
                        Label("Regenerate Briefing", systemImage: "arrow.clockwise")
                    }
                    .disabled(isGenerating)

                    Button {
                        showFactsSheet = true
                    } label: {
                        Label("What Claude Was Told", systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(facts == nil)

                    Divider()

                    Toggle(isOn: $autoGenerate) {
                        Label("Generate Automatically", systemImage: "wand.and.stars")
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showFactsSheet) {
            factsSheet
        }
        .task {
            await refresh()
        }
        .refreshable {
            await refresh()
        }
    }

    // MARK: - Sections

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(timeOfDayGreeting)
                .font(.largeTitle.bold())
        }
    }

    private var timeOfDayGreeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 0..<5: return "Still up"
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    @ViewBuilder
    private var narrativeCard: some View {
        BriefingCard(title: "Your Plan", systemImage: "sparkles", tint: .indigo) {
            if isGenerating {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Writing your briefing…")
                        .foregroundStyle(.secondary)
                }
            } else if let briefing = todaysBriefing, !briefing.narrative.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(markdown(briefing.narrative))
                        .font(.body)
                    Text("Written by \(ClaudeModel(rawValue: briefing.usedModelRawValue)?.displayName ?? "Claude") at \(briefing.generatedAt, format: .dateTime.hour().minute())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                    Button("Try Again") {
                        Task { await generate(force: true) }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("The facts below are ready. Add an Anthropic API key in Settings and Claude will turn them into a prioritized plan each morning.")
                        .foregroundStyle(.secondary)
                    Button("Write Today's Briefing") {
                        Task { await generate(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private func calendarCard(facts: BriefingService.Facts) -> some View {
        BriefingCard(title: "Schedule", systemImage: "calendar", tint: .red) {
            if facts.events.isEmpty && facts.reminders.isEmpty {
                Text(calendarAuthorized ? "Nothing on the calendar today." : "Calendar access is off.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(facts.events) { event in
                        AgendaRow(entry: event)
                    }
                    if !facts.reminders.isEmpty {
                        if !facts.events.isEmpty { Divider() }
                        ForEach(facts.reminders) { reminder in
                            AgendaRow(entry: reminder)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func taskCards(facts: BriefingService.Facts) -> some View {
        if !facts.overdue.isEmpty {
            BriefingCard(title: "Overdue", systemImage: "exclamationmark.triangle.fill", tint: .orange) {
                taskList(facts.overdue)
            }
        }

        BriefingCard(title: "Due Today", systemImage: "checklist", tint: .blue) {
            if facts.dueToday.isEmpty {
                Text("Nothing due today.")
                    .foregroundStyle(.secondary)
            } else {
                taskList(facts.dueToday)
            }
        }

        if !facts.dueSoon.isEmpty {
            BriefingCard(title: "Coming Up", systemImage: "calendar.badge.clock", tint: .teal) {
                taskList(facts.dueSoon)
            }
        }
    }

    private func taskList(_ items: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items) { task in
                TaskRow(task: task, showsArea: true) {
                    withAnimation { task.complete() }
                }
            }
        }
    }

    @ViewBuilder
    private var accessPrompts: some View {
        if !calendarAuthorized || !remindersAuthorized {
            BriefingCard(title: "Connect Your Day", systemImage: "link", tint: .gray) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The briefing gets much better with your real schedule in it. Nothing is written back — this app only reads.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !calendarAuthorized {
                        Button("Allow Calendar Access") {
                            Task {
                                await CalendarService.shared.requestCalendarAccess()
                                await refresh()
                            }
                        }
                    }
                    if !remindersAuthorized {
                        Button("Allow Reminders Access") {
                            Task {
                                await CalendarService.shared.requestReminderAccess()
                                await refresh()
                            }
                        }
                    }
                }
            }
        }
    }

    private var factsSheet: some View {
        NavigationStack {
            ScrollView {
                Text(facts?.summaryText ?? "")
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Sent to Claude")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFactsSheet = false }
                }
            }
        }
    }

    // MARK: - Behavior

    private func refresh() async {
        isLoadingFacts = facts == nil
        calendarAuthorized = CalendarService.shared.isCalendarAuthorized
        remindersAuthorized = CalendarService.shared.isReminderAuthorized
        let gathered = await BriefingService.gatherFacts(tasks: tasks)
        facts = gathered
        isLoadingFacts = false

        if autoGenerate, todaysBriefing == nil, !gathered.isQuietDay {
            await generate(force: false)
        }
    }

    private func generate(force: Bool) async {
        guard let facts else { return }
        if !force, todaysBriefing != nil { return }

        guard let apiKey = KeychainHelper.read(), !apiKey.isEmpty else {
            // No key is a normal state, not a failure — the facts still stand.
            errorMessage = nil
            return
        }

        isGenerating = true
        errorMessage = nil
        do {
            let narrative = try await BriefingService.generateNarrative(
                facts: facts,
                model: model,
                apiKey: apiKey
            )
            if let existing = todaysBriefing {
                existing.narrative = narrative
                existing.factsSummary = facts.summaryText
                existing.generatedAt = .now
                existing.usedModelRawValue = model.rawValue
            } else {
                modelContext.insert(
                    DailyBriefing(
                        dayKey: todayKey,
                        narrative: narrative,
                        factsSummary: facts.summaryText,
                        usedModelRawValue: model.rawValue
                    )
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isGenerating = false
    }

    /// Renders the model's Markdown, falling back to the raw string if it
    /// contains something `AttributedString` can't parse.
    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

/// A titled card. The Today screen is a stack of these; giving them a shared
/// container keeps spacing and material consistent across sections.
struct BriefingCard<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// One calendar event or reminder.
struct AgendaRow: View {
    let entry: AgendaEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.source == .calendar ? "circle.fill" : "checkmark.circle")
                .font(.caption2)
                .foregroundStyle(entry.source == .calendar ? Color.red : Color.orange)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    Text(entry.timeDescription)
                    if let location = entry.location, !location.isEmpty {
                        Text("·")
                        Text(location).lineLimit(1)
                    }
                    Text("·")
                    Text(entry.calendarName).lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
