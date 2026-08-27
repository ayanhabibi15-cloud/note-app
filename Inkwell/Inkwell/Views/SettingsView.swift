import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("claudeModel") private var modelRawValue = ClaudeModel.sonnet.rawValue
    @AppStorage("autoGenerateBriefing") private var autoGenerateBriefing = true
    @AppStorage("pencilOnlyByDefault") private var pencilOnlyByDefault = false

    @Query private var documents: [StoredDocument]
    @Query private var briefings: [DailyBriefing]

    @State private var apiKey: String = KeychainHelper.read() ?? ""
    @State private var savedConfirmation = false
    @State private var calendarAuthorized = false
    @State private var remindersAuthorized = false

    private var model: ClaudeModel { ClaudeModel(rawValue: modelRawValue) ?? .sonnet }

    private var libraryBytes: Int {
        documents.reduce(0) { $0 + $1.byteCount }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Inkwell")
                            .font(.title2.bold())
                        Text("Notes, tasks, documents, and a daily briefing in one place — for school, home, activities, and outside projects.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    SecureField("Anthropic API key", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif

                    Button("Save API Key") {
                        KeychainHelper.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        savedConfirmation = true
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)

                    if !apiKey.isEmpty {
                        Button("Remove API Key", role: .destructive) {
                            KeychainHelper.delete()
                            apiKey = ""
                            savedConfirmation = false
                        }
                    }
                } header: {
                    Text("Claude")
                } footer: {
                    if savedConfirmation {
                        Text("Saved to this device's Keychain.")
                    } else {
                        Text("Stored only in this device's Keychain and sent directly to api.anthropic.com. Every AI feature is optional — notes, tasks, and documents all work without a key.")
                    }
                }

                Section {
                    Picker("Model", selection: $modelRawValue) {
                        ForEach(ClaudeModel.allCases) { option in
                            VStack(alignment: .leading) {
                                Text(option.displayName)
                                Text(option.blurb).font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Default Model")
                }

                Section {
                    Toggle("Write a briefing each morning", isOn: $autoGenerateBriefing)
                    LabeledContent("Calendar", value: calendarAuthorized ? "Allowed" : "Not allowed")
                    LabeledContent("Reminders", value: remindersAuthorized ? "Allowed" : "Not allowed")
                    if !calendarAuthorized || !remindersAuthorized {
                        Button("Request Access") {
                            Task {
                                if !calendarAuthorized { await CalendarService.shared.requestCalendarAccess() }
                                if !remindersAuthorized { await CalendarService.shared.requestReminderAccess() }
                                refreshAuthorization()
                            }
                        }
                    }
                    if !briefings.isEmpty {
                        Button("Clear Saved Briefings (\(briefings.count))", role: .destructive) {
                            for briefing in briefings { modelContext.delete(briefing) }
                        }
                    }
                } header: {
                    Text("Morning Briefing")
                } footer: {
                    Text("The briefing reads your calendar and reminders — it never writes to them. Access is also changeable in the system Settings app.")
                }

                Section {
                    Toggle("Apple Pencil only by default", isOn: $pencilOnlyByDefault)
                } header: {
                    Text("Note-Taking")
                } footer: {
                    Text("Ignores finger touches while drawing, so you can rest your hand on the page.")
                }

                Section {
                    LabeledContent("Documents", value: "\(documents.count)")
                    LabeledContent("Storage used", value: ByteCountFormatter.string(fromByteCount: Int64(libraryBytes), countStyle: .file))
                } header: {
                    Text("Library")
                } footer: {
                    Text("Documents are stored in this app's Documents folder, so the whole library is also browsable in the Files app and in Finder.")
                }

                Section("About") {
                    LabeledContent("Version", value: "2.0")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: refreshAuthorization)
        }
    }

    private func refreshAuthorization() {
        calendarAuthorized = CalendarService.shared.isCalendarAuthorized
        remindersAuthorized = CalendarService.shared.isReminderAuthorized
    }
}
