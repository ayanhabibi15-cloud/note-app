import SwiftUI
import SwiftData

/// Create or edit a task. The same sheet does both: passing `nil` builds a new
/// one on save, passing a task edits it in place.
struct TaskEditorView: View {
    let task: TaskItem?
    let defaultArea: LifeArea

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Notebook.title) private var notebooks: [Notebook]

    @State private var title = ""
    @State private var details = ""
    @State private var area: LifeArea = .school
    @State private var course = ""
    @State private var priority: TaskPriority = .none
    @State private var recurrence: TaskRecurrence = .none
    @State private var hasDueDate = false
    @State private var hasDueTime = false
    @State private var dueDate = Calendar.current.startOfDay(for: .now)
    @State private var subtasks: [Subtask] = []
    @State private var newSubtask = ""
    @State private var linkedNotebookID: PersistentIdentifier?

    private var isEditing: Bool { task != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs doing?", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.headline)
                    TextField("Notes", text: $details, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("Area") {
                    Picker("Area", selection: $area) {
                        ForEach(LifeArea.allCases) { option in
                            Label(option.title, systemImage: option.symbolName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField(courseFieldPrompt, text: $course)
                }

                Section("When") {
                    Toggle("Due date", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker(
                            "Date",
                            selection: $dueDate,
                            displayedComponents: hasDueTime ? [.date, .hourAndMinute] : [.date]
                        )
                        Toggle("Set a time", isOn: $hasDueTime.animation())
                        Picker("Repeat", selection: $recurrence) {
                            ForEach(TaskRecurrence.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    }
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Steps") {
                    ForEach($subtasks) { $subtask in
                        HStack(spacing: 12) {
                            Button {
                                subtask.isDone.toggle()
                            } label: {
                                Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(subtask.isDone ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            TextField("Step", text: $subtask.title)
                                .strikethrough(subtask.isDone, color: .secondary)
                        }
                    }
                    .onDelete { subtasks.remove(atOffsets: $0) }

                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
                        TextField("Add a step", text: $newSubtask)
                            .onSubmit(addSubtask)
                            .submitLabel(.done)
                    }
                }

                Section {
                    Picker("Notebook", selection: $linkedNotebookID) {
                        Text("None").tag(PersistentIdentifier?.none)
                        ForEach(notebooks) { notebook in
                            Text(notebook.title).tag(PersistentIdentifier?.some(notebook.persistentModelID))
                        }
                    }
                } header: {
                    Text("Linked Notebook")
                } footer: {
                    Text("Link a notebook and this task becomes a shortcut into the pages for it.")
                }

                if let task {
                    Section {
                        Button(role: .destructive) {
                            modelContext.delete(task)
                            dismiss()
                        } label: {
                            Label("Delete Task", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Task" : "New Task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    /// The "course" field means something different in each area, so the
    /// placeholder changes rather than making the user guess.
    private var courseFieldPrompt: String {
        switch area {
        case .school: return "Class (e.g. AP Biology)"
        case .home: return "Who or where (e.g. Kitchen)"
        case .eca: return "Club or team"
        case .projects: return "Project or client"
        case .personal: return "Tag"
        }
    }

    private func addSubtask() {
        let trimmed = newSubtask.trimmingCharacters(in: .whitespaces)
        newSubtask = ""
        guard !trimmed.isEmpty else { return }
        subtasks.append(Subtask(title: trimmed))
    }

    private func load() {
        guard let task else {
            area = defaultArea
            return
        }
        title = task.title
        details = task.details
        area = task.area
        course = task.course
        priority = task.priority
        recurrence = task.recurrence
        subtasks = task.subtasks
        linkedNotebookID = task.notebook?.persistentModelID
        if let due = task.dueDate {
            hasDueDate = true
            hasDueTime = task.hasDueTime
            dueDate = due
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        // Strip the time component when the user didn't ask for one, so
        // "due Friday" doesn't silently become "due Friday at 9:41".
        let resolvedDue: Date? = {
            guard hasDueDate else { return nil }
            return hasDueTime ? dueDate : Calendar.current.startOfDay(for: dueDate)
        }()

        let linkedNotebook: Notebook? = linkedNotebookID.flatMap {
            modelContext.model(for: $0) as? Notebook
        }

        let target: TaskItem
        if let task {
            target = task
        } else {
            target = TaskItem(title: trimmedTitle, area: area)
            modelContext.insert(target)
        }

        target.title = trimmedTitle
        target.details = details
        target.area = area
        target.course = course.trimmingCharacters(in: .whitespaces)
        target.priority = priority
        target.recurrence = hasDueDate ? recurrence : .none
        target.dueDate = resolvedDue
        target.hasDueTime = hasDueDate && hasDueTime
        target.subtasks = subtasks.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        target.notebook = linkedNotebook
        target.updatedAt = .now

        dismiss()
    }
}
