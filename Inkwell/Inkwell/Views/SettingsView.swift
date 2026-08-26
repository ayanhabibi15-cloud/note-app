import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("claudeModel") private var modelRawValue = ClaudeModel.sonnet.rawValue

    @State private var apiKey: String = KeychainHelper.read() ?? ""
    @State private var savedConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Inkwell")
                        .font(.title2.bold())
                    Text("A handwriting-first notebook app with folders, paper templates, and an optional Claude-powered study assistant.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Claude AI Assistant") {
                    SecureField("Anthropic API key", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif

                    Picker("Default model", selection: $modelRawValue) {
                        ForEach(ClaudeModel.allCases) { model in
                            Text(model.displayName).tag(model.rawValue)
                        }
                    }

                    Button("Save API Key") {
                        KeychainHelper.save(apiKey)
                        savedConfirmation = true
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)

                    if !apiKey.isEmpty {
                        Button("Remove API Key", role: .destructive) {
                            KeychainHelper.delete()
                            apiKey = ""
                        }
                    }

                    Text("Your API key is stored only in this device's Keychain. It's sent directly to Anthropic when you use the AI assistant — never anywhere else.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } footer: {
                    if savedConfirmation {
                        Text("Saved.")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
