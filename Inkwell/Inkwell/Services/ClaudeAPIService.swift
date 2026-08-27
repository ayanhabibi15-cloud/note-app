import Foundation

/// Which Claude model to call. Sonnet is the default — fast and inexpensive
/// for summaries, briefings, and Q&A over a page or two of notes. Opus is
/// offered for harder reasoning over long documents, Haiku for when you want
/// the cheapest possible pass.
enum ClaudeModel: String, CaseIterable, Identifiable {
    case sonnet = "claude-sonnet-5"
    case opus = "claude-opus-5"
    case haiku = "claude-haiku-4-5-20251001"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sonnet: return "Claude Sonnet"
        case .opus: return "Claude Opus"
        case .haiku: return "Claude Haiku"
        }
    }

    var blurb: String {
        switch self {
        case .sonnet: return "Balanced. The right default for daily use."
        case .opus: return "Strongest reasoning. Best for long documents and planning."
        case .haiku: return "Fastest and cheapest. Good for short summaries."
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

/// One turn in a conversation, in the shape the Messages API expects.
struct ClaudeMessage: Codable, Equatable {
    let role: String
    let content: String

    static func user(_ text: String) -> ClaudeMessage { ClaudeMessage(role: "user", content: text) }
    static func assistant(_ text: String) -> ClaudeMessage { ClaudeMessage(role: "assistant", content: text) }
}

/// Thin client for Anthropic's Messages API.
///
/// Everything that reaches this class is opt-in: the note-taking, task, and
/// document features all work with no API key at all, and nothing is sent
/// anywhere until the user asks a question or generates a briefing. The key
/// lives in the Keychain and goes straight to `api.anthropic.com`.
struct ClaudeAPIService {
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"

    /// Sends a full conversation and returns the assistant's reply text.
    func send(
        messages: [ClaudeMessage],
        system: String,
        model: ClaudeModel,
        maxTokens: Int = 2048,
        apiKey: String
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw ClaudeAPIError.missingAPIKey }
        guard !messages.isEmpty else { throw ClaudeAPIError.badResponse("Nothing to send.") }

        let body = MessagesRequest(
            model: model.rawValue,
            max_tokens: maxTokens,
            system: system,
            messages: messages.map { .init(role: $0.role, content: $0.content) }
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
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
        let text = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")

        guard !text.isEmpty else {
            throw ClaudeAPIError.badResponse("Claude returned an empty response.")
        }
        return text
    }

    /// Single-shot convenience used by the note-page assistant: one question
    /// asked against one page of recognized text.
    func ask(
        prompt: String,
        noteContext: String,
        model: ClaudeModel,
        apiKey: String
    ) async throws -> String {
        let systemPrompt = """
        You are a study assistant embedded in a handwriting note-taking app. \
        You are given the recognized text and typed text from the user's current \
        note page, followed by a question or instruction from the user. Answer \
        concisely and reference the notes directly when useful. If the recognized \
        text looks garbled, say so rather than guessing at what it meant.
        """

        let userContent = "Notes from the current page:\n\n\(noteContext)\n\n---\n\nRequest: \(prompt)"

        return try await send(
            messages: [.user(userContent)],
            system: systemPrompt,
            model: model,
            maxTokens: 1024,
            apiKey: apiKey
        )
    }
}

private struct MessagesRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String
    let max_tokens: Int
    let system: String
    let messages: [Message]
}

private struct MessagesResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        /// Optional so a non-text block (should the API ever return one)
        /// doesn't fail the whole decode.
        let text: String?
    }
    let content: [ContentBlock]
}

private struct ErrorEnvelope: Decodable {
    struct ErrorDetail: Decodable { let message: String }
    let error: ErrorDetail
}
