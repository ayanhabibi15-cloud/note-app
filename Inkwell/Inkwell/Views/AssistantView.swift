import SwiftUI
import SwiftData
import UIKit

/// The full assistant: a conversation with Claude that can see the workspace.
///
/// What "see" means is deliberately narrow and visible. Before each send, the
/// app builds a plain-text picture of the areas you've put in scope — open
/// tasks, notebook titles, the calendar, and the text of documents you pinned
/// or attached — and shows you a one-line summary of it under the message. The
/// picture is rebuilt each turn, so answers reflect what's true right now
/// rather than what was true when the thread started.
struct AssistantView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ChatThread.updatedAt, order: .reverse) private var threads: [ChatThread]
    @Query private var tasks: [TaskItem]
    @Query private var notebooks: [Notebook]
    @Query(sort: \StoredDocument.addedAt, order: .reverse) private var documents: [StoredDocument]

    @AppStorage("claudeModel") private var modelRawValue = ClaudeModel.sonnet.rawValue

    @State private var activeThreadID: PersistentIdentifier?
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var attachedDocumentIDs: Set<PersistentIdentifier> = []
    @State private var showScopeSheet = false
    @State private var showThreadList = false

    private var model: ClaudeModel { ClaudeModel(rawValue: modelRawValue) ?? .sonnet }

    private var activeThread: ChatThread? {
        if let activeThreadID, let thread = modelContext.model(for: activeThreadID) as? ChatThread {
            return thread
        }
        return threads.first
    }

    var body: some View {
        VStack(spacing: 0) {
            transcript
            Divider()
            composer
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(activeThread?.title ?? "Assistant")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newThread()
                } label: {
                    Label("New Conversation", systemImage: "square.and.pencil")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showThreadList = true
                } label: {
                    Label("Conversations", systemImage: "bubble.left.and.bubble.right")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Picker("Model", selection: $modelRawValue) {
                        ForEach(ClaudeModel.allCases) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                } label: {
                    Label(model.displayName, systemImage: "cpu")
                }
            }
        }
        .sheet(isPresented: $showThreadList) { threadListSheet }
        .sheet(isPresented: $showScopeSheet) { scopeSheet }
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcript: some View {
        if let thread = activeThread, !thread.messages.isEmpty {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(thread.sortedMessages) { message in
                            MessageBubble(message: message)
                                .id(message.persistentModelID)
                        }
                        if isSending {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Thinking…").foregroundStyle(.secondary)
                            }
                            .id("thinking")
                        }
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: thread.messages.count) { _, _ in
                    guard let lastID = thread.sortedMessages.last?.persistentModelID else { return }
                    withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                }
                .onChange(of: isSending) { _, sending in
                    if sending { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
                }
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundStyle(.indigo)
                    .padding(.top, 60)

                VStack(spacing: 8) {
                    Text("Ask about your own work")
                        .font(.title2.bold())
                    Text("The assistant can see your open tasks, your notebook titles, today's calendar, and the text of any document you've pinned or attached.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    ForEach(Self.starters, id: \.self) { starter in
                        Button {
                            draft = starter
                        } label: {
                            Text(starter)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if KeychainHelper.read()?.isEmpty != false {
                    Label("Add an Anthropic API key in Settings to start.", systemImage: "key")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }

    private static let starters = [
        "What should I work on first today, and why?",
        "Turn my overdue tasks into a realistic plan for this week.",
        "Quiz me on the pinned document.",
        "Draft an outline for my project based on the brief I filed.",
        "What am I forgetting?"
    ]

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 10) {
            if !attachedDocumentIDs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachedDocuments) { document in
                            HStack(spacing: 6) {
                                Image(systemName: document.kind.symbolName)
                                Text(document.title).lineLimit(1)
                                Button {
                                    attachedDocumentIDs.remove(document.persistentModelID)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.indigo.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    Button {
                        showScopeSheet = true
                    } label: {
                        Label("Choose Areas & Documents", systemImage: "slider.horizontal.3")
                    }
                    if !documents.isEmpty {
                        Divider()
                        ForEach(documents.prefix(12)) { document in
                            Button {
                                attachedDocumentIDs.insert(document.persistentModelID)
                            } label: {
                                Label(document.title, systemImage: document.kind.symbolName)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "paperclip")
                        .font(.title3)
                        .frame(width: 34, height: 34)
                }

                TextField("Ask anything about your work…", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                }
                .buttonStyle(.plain)
                .disabled(isSending || draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                Text(contextSummaryPreview)
                Spacer()
                Button("Scope") { showScopeSheet = true }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.bar)
    }

    private var attachedDocuments: [StoredDocument] {
        documents.filter { attachedDocumentIDs.contains($0.persistentModelID) }
    }

    // MARK: - Scope

    private var contextOptions: WorkspaceContext.Options {
        var options = WorkspaceContext.Options()
        options.areas = activeThread?.scope ?? Set(LifeArea.allCases)
        options.attachedDocumentIDs = attachedDocumentIDs
        return options
    }

    /// A cheap description of what the next question will carry. Deliberately
    /// counts rather than assembling: `assemble` splices in whole documents,
    /// which is far too expensive to run on every keystroke.
    private var contextSummaryPreview: String {
        let areas = contextOptions.areas
        var parts: [String] = []

        let openTasks = tasks.filter { !$0.isDone && areas.contains($0.area) }.count
        if openTasks > 0 { parts.append("\(openTasks) open task\(openTasks == 1 ? "" : "s")") }

        let sharedDocuments = documents.filter { document in
            attachedDocumentIDs.contains(document.persistentModelID)
                || (document.isPinnedToAssistant && areas.contains(document.area))
        }.count
        if sharedDocuments > 0 { parts.append("\(sharedDocuments) document\(sharedDocuments == 1 ? "" : "s")") }

        let areaNames = LifeArea.allCases.filter { areas.contains($0) }.map(\.title)
        if areaNames.count == LifeArea.allCases.count {
            parts.append("all areas")
        } else if areaNames.isEmpty {
            return "No workspace context attached"
        } else {
            parts.append(areaNames.joined(separator: ", "))
        }

        return "Sharing " + parts.joined(separator: " · ")
    }

    private var scopeSheet: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(LifeArea.allCases) { area in
                        Toggle(isOn: scopeBinding(for: area)) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(area.title)
                                    Text(area.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: area.symbolName)
                                    .foregroundStyle(area.color)
                            }
                        }
                    }
                } header: {
                    Text("Areas in Scope")
                } footer: {
                    Text("Tasks, notebooks, and pinned documents from these areas are shared with Claude on each question.")
                }

                if !documents.isEmpty {
                    Section {
                        ForEach(documents) { document in
                            Toggle(isOn: attachmentBinding(for: document)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(document.title)
                                    Text(document.hasText ? "\(document.extractedText.count) characters" : "No readable text")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .disabled(!document.hasText)
                        }
                    } header: {
                        Text("Attach Documents to This Question")
                    } footer: {
                        Text("Attached documents are sent in full, whatever their area.")
                    }
                }
            }
            .navigationTitle("What Claude Sees")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showScopeSheet = false }
                }
            }
        }
    }

    private func scopeBinding(for area: LifeArea) -> Binding<Bool> {
        Binding(
            get: { activeThread?.scope.contains(area) ?? true },
            set: { isOn in
                guard let thread = activeThread else { return }
                var scope = thread.scope
                if isOn { scope.insert(area) } else { scope.remove(area) }
                thread.scope = scope
            }
        )
    }

    private func attachmentBinding(for document: StoredDocument) -> Binding<Bool> {
        Binding(
            get: { attachedDocumentIDs.contains(document.persistentModelID) },
            set: { isOn in
                if isOn {
                    attachedDocumentIDs.insert(document.persistentModelID)
                } else {
                    attachedDocumentIDs.remove(document.persistentModelID)
                }
            }
        )
    }

    private var threadListSheet: some View {
        NavigationStack {
            List {
                ForEach(threads) { thread in
                    Button {
                        activeThreadID = thread.persistentModelID
                        showThreadList = false
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(thread.title).font(.body)
                            Text("\(thread.messages.count) messages · \(thread.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    for index in indexSet { modelContext.delete(threads[index]) }
                }
            }
            .overlay {
                if threads.isEmpty {
                    ContentUnavailableView("No Conversations", systemImage: "bubble.left")
                }
            }
            .navigationTitle("Conversations")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showThreadList = false }
                }
            }
        }
    }

    // MARK: - Sending

    private func newThread() {
        let thread = ChatThread()
        modelContext.insert(thread)
        activeThreadID = thread.persistentModelID
        attachedDocumentIDs = []
        errorMessage = nil
    }

    private func send() async {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        guard let apiKey = KeychainHelper.read(), !apiKey.isEmpty else {
            errorMessage = ClaudeAPIError.missingAPIKey.errorDescription
            return
        }

        let thread: ChatThread
        if let existing = activeThread {
            thread = existing
        } else {
            thread = ChatThread()
            modelContext.insert(thread)
            activeThreadID = thread.persistentModelID
        }

        // Rebuild context every turn: tasks get checked off and documents get
        // added between messages, and a stale snapshot would quietly go wrong.
        let events = CalendarService.shared.events()
        let reminders = await CalendarService.shared.reminders()
        let context = WorkspaceContext.assemble(
            options: contextOptions,
            tasks: tasks,
            notebooks: notebooks,
            documents: documents,
            events: events,
            reminders: reminders
        )

        // Snapshot the history first: the request must not depend on when
        // SwiftData propagates the inverse relationship for the turn we're
        // about to insert.
        let history = thread.sortedMessages.map { ClaudeMessage(role: $0.role, content: $0.text) }

        let userMessage = ChatMessage(
            role: "user",
            text: question,
            contextSummary: context.summary,
            thread: thread
        )
        modelContext.insert(userMessage)
        thread.updatedAt = .now
        if thread.title == "New Conversation" {
            thread.title = String(question.prefix(48))
        }

        draft = ""
        errorMessage = nil
        isSending = true

        // History goes as plain turns; the workspace picture rides on the
        // latest turn only, so old context never contradicts current state.
        var payload = history
        payload.append(.user("""
        <workspace>
        \(context.text)
        </workspace>

        \(question)
        """))

        do {
            let reply = try await ClaudeAPIService().send(
                messages: payload,
                system: Self.systemPrompt,
                model: model,
                maxTokens: 3000,
                apiKey: apiKey
            )
            modelContext.insert(ChatMessage(role: "assistant", text: reply, thread: thread))
            thread.updatedAt = .now
            attachedDocumentIDs = []
        } catch {
            // The API requires strictly alternating roles, so a failed turn
            // can't be left behind — it would poison every later send. Roll it
            // back and hand the question to the user to retry.
            modelContext.delete(userMessage)
            draft = question
            errorMessage = error.localizedDescription
        }
        isSending = false
    }

    private static let systemPrompt = """
    You are the assistant inside a personal productivity app used by one \
    person to run their school work, home responsibilities, extracurricular \
    activities, and outside projects from a single place.

    Each user turn may be preceded by a <workspace> block containing a \
    snapshot of their current tasks, notebooks, calendar, and the text of \
    documents they chose to share. Treat it as ground truth about their \
    situation, and treat the most recent block as current — earlier blocks in \
    the conversation are stale.

    How to be useful here:
    - Be concrete. Name the actual tasks, classes, documents, and events.
    - Prioritize honestly. If they have more to do than the day holds, say \
      what to drop, not just what to do.
    - When asked to study or quiz, work from the shared documents and notes \
      rather than general knowledge, and say when the material doesn't cover \
      something.
    - Never invent a deadline, grade, event, or document you weren't given. If \
      you need something that isn't in the workspace, ask for it.
    - You cannot change their data. When the right answer is a new task or a \
      changed due date, say exactly what to add or change and let them do it.
    - Match the length of the answer to the question. A planning question \
      deserves structure; a factual one deserves a sentence.
    """
}

/// One turn in the transcript. User turns show the context summary underneath
/// so it's always visible what was attached to that specific question.
struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
            Text(rendered)
                .font(.body)
                .textSelection(.enabled)
                .padding(12)
                .background(
                    message.isUser ? Color.accentColor.opacity(0.14) : Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14)
                )

            if message.isUser, !message.contextSummary.isEmpty {
                Text(message.contextSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }

    private var rendered: AttributedString {
        (try? AttributedString(
            markdown: message.text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(message.text)
    }
}
