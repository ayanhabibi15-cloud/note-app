import SwiftUI
import PencilKit

/// Optional AI assistant panel. Recognizes the current page's handwriting
/// on-device with Vision, combines it with any typed text boxes, and sends
/// that plus the user's question to Claude. Entirely opt-in: it does nothing
/// until the user configures an API key in Settings and taps "Ask".
struct AIAssistantSheet: View {
    let page: Page?

    @AppStorage("claudeModel") private var modelRawValue = ClaudeModel.sonnet.rawValue
    @Environment(\.dismiss) private var dismiss

    @State private var question = ""
    @State private var recognizedText = ""
    @State private var isRecognizing = false
    @State private var isAsking = false
    @State private var answer = ""
    @State private var errorMessage: String?

    private var model: ClaudeModel { ClaudeModel(rawValue: modelRawValue) ?? .sonnet }
    private var apiKey: String? { KeychainHelper.read() }

    var body: some View {
        NavigationStack {
            Form {
                if apiKey == nil || apiKey?.isEmpty == true {
                    Section {
                        Label("Add an Anthropic API key in Settings to enable the AI assistant.", systemImage: "key.slash")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notes on This Page") {
                    if isRecognizing {
                        ProgressView("Reading handwriting…")
                    } else if recognizedText.isEmpty {
                        Text("No text recognized yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(recognizedText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                    }
                }

                Section("Ask Claude") {
                    Picker("Model", selection: $modelRawValue) {
                        ForEach(ClaudeModel.allCases) { model in
                            Text(model.displayName).tag(model.rawValue)
                        }
                    }
                    TextField("e.g. Summarize this page", text: $question, axis: .vertical)
                        .lineLimit(2...4)
                    Button {
                        Task { await ask() }
                    } label: {
                        if isAsking {
                            ProgressView()
                        } else {
                            Text("Ask")
                        }
                    }
                    .disabled(isAsking || question.trimmingCharacters(in: .whitespaces).isEmpty || apiKey == nil || apiKey?.isEmpty == true)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                if !answer.isEmpty {
                    Section("Answer") {
                        Text(answer)
                    }
                }
            }
            .navigationTitle("AI Assistant")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await recognizeCurrentPage() }
        }
    }

    private func recognizeCurrentPage() async {
        guard let page else { return }
        isRecognizing = true
        let drawing = (try? PKDrawing(data: page.drawingData)) ?? PKDrawing()
        let text = await HandwritingRecognizer.recognizeText(from: drawing, pageSize: PageSize.standard)
        let typed = page.textBoxes.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
        recognizedText = [text, typed].filter { !$0.isEmpty }.joined(separator: "\n\n")
        isRecognizing = false
    }

    private func ask() async {
        guard let apiKey, !apiKey.isEmpty else {
            errorMessage = ClaudeAPIError.missingAPIKey.errorDescription
            return
        }
        isAsking = true
        errorMessage = nil
        answer = ""
        do {
            let service = ClaudeAPIService()
            let result = try await service.ask(
                prompt: question,
                noteContext: recognizedText.isEmpty ? "(No text recognized on this page.)" : recognizedText,
                model: model,
                apiKey: apiKey
            )
            answer = result
        } catch {
            errorMessage = error.localizedDescription
        }
        isAsking = false
    }
}
