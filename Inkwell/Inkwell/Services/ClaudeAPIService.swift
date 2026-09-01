import Foundation

/// Which Claude model the AI assistant should call. Opus is the default —
/// the strongest reasoning on long, dense notebooks; Sonnet and Haiku are
/// offered for people who want faster, cheaper answers.
enum ClaudeModel: String, CaseIterable, Identifiable {
    case opus = "claude-opus-5"
    case sonnet = "claude-sonnet-5"
    case haiku = "claude-haiku-4-5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opus: return "Claude Opus 5"
        case .sonnet: return "Claude Sonnet 5"
        case .haiku: return "Claude Haiku 4.5"
        }
    }

    /// Only the current top-tier models accept the effort setting.
    var supportsEffort: Bool {
        switch self {
        case .opus, .sonnet: return true
        case .haiku: return false
        }
    }
}

enum ClaudeAPIError: LocalizedError {
    case missingAPIKey
    case badResponse(String)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your Anthropic API key in Settings to use the AI assistant."
        case .badResponse(let message):
            return message
        case .network(let error):
            return error.localizedDescription
        }
    }
}

/// Thin client for Anthropic's Messages API. This is intentionally optional
/// and off by default: nothing about the note-taking experience depends on
/// it, and no note content is sent anywhere unless the user explicitly asks
/// the assistant a question and has configured an API key.
struct ClaudeAPIService {
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"

    func ask(
        prompt: String,
        noteContext: String,
        model: ClaudeModel,
        apiKey: String
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw ClaudeAPIError.missingAPIKey }

        let systemPrompt = """
        You are a study assistant embedded in a handwriting note-taking app. \
        You are given the recognized text and typed text from the user's current \
        note page, followed by a question or instruction from the user. Answer \
        concisely and reference the notes directly when useful.
        """

        let userContent = "Notes from the current page:\n\n\(noteContext)\n\n---\n\nRequest: \(prompt)"

        // Thinking is on by default on the current models and draws from the
        // same budget as the answer, so leave plenty of headroom here.
        let body = MessagesRequest(
            model: model.rawValue,
            max_tokens: 16000,
            system: systemPrompt,
            messages: [.init(role: "user", content: userContent)],
            output_config: model.supportsEffort ? .init(effort: "medium") : nil
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClaudeAPIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeAPIError.badResponse("No response from server.")
        }

        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.message
            throw ClaudeAPIError.badResponse(message ?? "Request failed with status \(http.statusCode).")
        }

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)

        if decoded.stop_reason == "refusal" {
            throw ClaudeAPIError.badResponse("Claude declined to answer this one.")
        }

        let answer = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !answer.isEmpty else {
            throw ClaudeAPIError.badResponse("No answer came back — try rephrasing the question.")
        }
        return answer
    }
}

private struct MessagesRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    struct OutputConfig: Encodable {
        let effort: String
    }
    let model: String
    let max_tokens: Int
    let system: String
    let messages: [Message]
    let output_config: OutputConfig?
}

private struct MessagesResponse: Decodable {
    /// Responses also carry thinking blocks, which have no `text`, so this
    /// stays optional and callers filter on `type`.
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
    let content: [ContentBlock]
    let stop_reason: String?
}

private struct ErrorEnvelope: Decodable {
    struct ErrorDetail: Decodable { let message: String }
    let error: ErrorDetail
}
