import Foundation

/// Which Claude model the AI assistant should call. Sonnet is the default —
/// fast and inexpensive for summaries and Q&A over a page or two of notes;
/// Opus is offered for people who want the strongest reasoning on long,
/// dense notebooks.
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

        let body = MessagesRequest(
            model: model.rawValue,
            max_tokens: 1024,
            system: systemPrompt,
            messages: [.init(role: "user", content: userContent)]
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
        return decoded.content.map(\.text).joined(separator: "\n")
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
        let text: String
    }
    let content: [ContentBlock]
}

private struct ErrorEnvelope: Decodable {
    struct ErrorDetail: Decodable { let message: String }
    let error: ErrorDetail
}
