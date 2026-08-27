import SwiftUI
import SwiftData

/// How the task list is grouped. Time is the default because that's the
/// question you actually ask a to-do list; area grouping is there for the
/// weekly "what's the state of my projects" pass.
enum TaskGrouping: String, CaseIterable, Identifiable {
    case time
    case area
    case priority

    var id: String { rawValue }

    var title: String {
        switch self {
        case .time: return "By Date"
        case .area: return "By Area"
        case .priority: return "By Priority"
        }
    }
}

/// The to-do list. One list for school, home, activities, and outside
/// projects, filterable down to any of them — the whole point of the app being
/// one app is that the deadline for a club form and the deadline for a lab
/// report land in the same place.
struct TasksView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TaskItem.createdAt, order: .reverse) private var allTasks: [TaskItem]

    @State private var grouping: TaskGrouping = .time
    @State private var areaFilter: LifeArea?
    @State private var showCompleted = false
    @State private var searchText = ""
    @State private var editingTask: TaskItem?
    @State private var isCreating = false
    @State private var quickEntry = ""

    private var filtered: [TaskItem] {
        allTasks.filter { task in
            if !showCompleted && task.isDone { return false }
            if let areaFilter, task.area != areaFilter { return false }
            guard !searchText.isEmpty else { return true }
            let needle = searchText.lowercased()
            return task.title.lowercased().contains(needle)
                || task.details.lowercased().contains(needle)
                || task.course.lowercased().contains(needle)
        }
    }

    var body: some View {
        List {
            quickAddRow

            ForEach(groups, id: \.title) { group in
                Section {
                    ForEach(group.tasks) { task in
                        TaskRow(task: task, showsArea: grouping != .area) {
                            withAnimation { task.complete() }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editingTask = task }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(task)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                withAnimation { task.isDone ? task.reopen() : task.complete() }
                            } label: {
                                Label(task.isDone ? "Reopen" : "Done", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
                            }
                            .tint(task.isDone ? .orange : .green)
                        }
                    }
                } header: {
                    HStack {
                        Text(group.title)
                        Spacer()
                        Text("\(group.tasks.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if groups.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Nothing to Do" : "No Matches",
                    systemImage: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "Add a task above, or switch on completed tasks to see what you've finished."
                        : "No task matches “\(searchText)”.")
                )
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search tasks")
        .navigationTitle(areaFilter?.title ?? "Tasks")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreating = true
                } label: {
                    Label("New Task", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Picker("Group By", selection: $grouping) {
                        ForEach(TaskGrouping.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    Divider()

                    Picker("Area", selection: $areaFilter) {
                        Text("All Areas").tag(LifeArea?.none)
                        ForEach(LifeArea.allCases) { area in
                            Label(area.title, systemImage: area.symbolName).tag(LifeArea?.some(area))
                        }
                    }

                    Divider()

                    Toggle(isOn: $showCompleted) {
                        Label("Show Completed", systemImage: "checkmark.circle")
                    }
                } label: {
                    Label("View Options", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            TaskEditorView(task: nil, defaultArea: areaFilter ?? .school)
        }
        .sheet(item: $editingTask) { task in
            TaskEditorView(task: task, defaultArea: task.area)
        }
    }

    // MARK: - Quick add

    private var quickAddRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.tint)
            TextField("Add a task…", text: $quickEntry)
                .onSubmit(commitQuickEntry)
                .submitLabel(.done)
        }
        .listRowBackground(Color.clear)
    }

    /// Quick entry understands a couple of shorthands so capture stays fast:
    /// `#school` sets the area, `!!` sets priority, and `today` / `tomorrow`
    /// set a due date. Anything it doesn't recognize stays in the title.
    private func commitQuickEntry() {
        let raw = quickEntry.trimmingCharacters(in: .whitespaces)
        quickEntry = ""
        guard !raw.isEmpty else { return }

        var words = raw.split(separator: " ").map(String.init)
        var area = areaFilter ?? .school
        var priority = TaskPriority.none
        var dueDate: Date?

        words.removeAll { word in
            let lower = word.lowercased()
            if lower.hasPrefix("#"), let matched = LifeArea(rawValue: String(lower.dropFirst())) {
                area = matched
                return true
            }
            if lower == "!!!" { priority = .high; return true }
            if lower == "!!" { priority = .medium; return true }
            if lower == "!" { priority = .low; return true }
            if lower == "today" {
                dueDate = Calendar.current.startOfDay(for: .now)
                return true
            }
            if lower == "tomorrow" {
                dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))
                return true
            }
            return false
        }

        let title = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let task = TaskItem(
            title: title.isEmpty ? raw : title,
            area: area,
            priority: priority,
            dueDate: dueDate
        )
        modelContext.insert(task)
    }

    // MARK: - Grouping

    private struct GroupedTasks {
        let title: String
        let tasks: [TaskItem]
    }

    private var groups: [GroupedTasks] {
        switch grouping {
        case .time: return timeGroups
        case .area: return areaGroups
        case .priority: return priorityGroups
        }
    }

    private var timeGroups: [GroupedTasks] {
        let calendar = Calendar.current
        let open = filtered.filter { !$0.isDone }
        let done = filtered.filter(\.isDone)

        let overdue = open.filter(\.isOverdue)
        let today = open.filter { $0.isDueToday && !$0.isOverdue }
        let tomorrow = open.filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDateInTomorrow(due)
        }
        let thisWeek = open.filter { task in
            guard let due = task.dueDate, !task.isOverdue, !task.isDueToday, !calendar.isDateInTomorrow(due) else { return false }
            return due < Date.now.addingTimeInterval(7 * 86_400)
        }
        let later = open.filter { task in
            guard let due = task.dueDate else { return false }
            return due >= Date.now.addingTimeInterval(7 * 86_400)
        }
        let noDate = open.filter { $0.dueDate == nil }

        return build([
            ("Overdue", overdue),
            ("Today", today),
            ("Tomorrow", tomorrow),
            ("This Week", thisWeek),
            ("Later", later),
            ("No Due Date", noDate),
            ("Completed", done)
        ])
    }

    private var areaGroups: [GroupedTasks] {
        build(LifeArea.allCases.map { area in
            (area.title, filtered.filter { $0.area == area })
        })
    }

    private var priorityGroups: [GroupedTasks] {
        build(TaskPriority.allCases.reversed().map { priority in
            (priority == .none ? "No Priority" : "\(priority.title) Priority",
             filtered.filter { $0.priority == priority })
        })
    }

    private func build(_ pairs: [(String, [TaskItem])]) -> [GroupedTasks] {
        pairs.compactMap { title, tasks in
            guard !tasks.isEmpty else { return nil }
            return GroupedTasks(title: title, tasks: tasks.sorted(by: defaultOrder))
        }
    }

    private func defaultOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.isDone != rhs.isDone { return !lhs.isDone }
        if lhs.priority.rawValue != rhs.priority.rawValue {
            return lhs.priority.rawValue > rhs.priority.rawValue
        }
        return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
    }
}

/// One task, used in both the task list and the Today screen. The checkbox is
/// its own hit target so tapping the row can mean "open" while tapping the
/// circle means "done" — the same split Reminders uses.
struct TaskRow: View {
    @Bindable var task: TaskItem
    var showsArea: Bool = true
    var onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Mark not done" : "Mark done")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if task.priority != .none {
                        Text(task.priority.flagText)
                            .font(.subheadline.bold())
                            .foregroundStyle(task.priority == .high ? Color.red : Color.orange)
                    }
                    Text(task.title)
                        .font(.body)
                        .strikethrough(task.isDone, color: .secondary)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                }

                if !task.details.isEmpty {
                    Text(task.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if showsArea {
                        Label(task.area.title, systemImage: task.area.symbolName)
                            .font(.caption2)
                            .foregroundStyle(task.area.color)
                    }
                    if !task.course.isEmpty {
                        Text(task.course)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let due = task.dueDate {
                        Label(
                            WorkspaceContext.format(due, withTime: task.hasDueTime),
                            systemImage: "calendar"
                        )
                        .font(.caption2)
                        .foregroundStyle(task.isOverdue ? Color.red : Color.secondary)
                    }
                    if task.recurrence != .none {
                        Image(systemName: "repeat")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    let openSubtasks = task.subtasks.filter { !$0.isDone }.count
                    if !task.subtasks.isEmpty {
                        Text("\(task.subtasks.count - openSubtasks)/\(task.subtasks.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
