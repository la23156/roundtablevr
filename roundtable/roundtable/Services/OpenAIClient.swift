//
//  OpenAIClient.swift
//  roundtable
//
//  LLM client for strict-JSON-schema turn generation, now via OpenRouter
//  (chat completions API). Director turns run on Anthropic's frontier
//  claude-fable-5.1 (reasoning is mandatory there; "low" effort keeps it
//  ~6 s, hidden by the 2-turn buffer); interjection replies use
//  claude-sonnet-5 with reasoning off (~4 s) for latency.
//

import Foundation

struct OpenAIClient {
    enum ClientError: LocalizedError {
        case http(Int, String)
        case emptyOutput

        var errorDescription: String? {
            switch self {
            case .http(let code, let body): return "OpenRouter HTTP \(code): \(body.prefix(300))"
            case .emptyOutput: return "OpenRouter response contained no message content"
            }
        }
    }

    var model = "anthropic/claude-fable-5.1"
    /// Faster model for latency-critical replies to the user.
    var fastModel = "anthropic/claude-sonnet-5"

    /// Generates the next roundtable turn as strict structured output.
    /// `fast` selects the low-latency model (used for interjection replies).
    func generateTurn(
        system: String,
        input: String,
        castIDs: [String],
        fast: Bool = false
    ) async throws -> DirectorTurn {
        let lookTargets = castIDs + ["user", "table"]
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "speaker": ["type": "string", "enum": castIDs],
                "text": ["type": "string"],
                "emotion": ["type": "string", "enum": Emotion.allCases.map(\.rawValue)],
                "look_target": ["type": "string", "enum": lookTargets],
                "gesture": ["type": "string", "enum": Gesture.allCases.map(\.rawValue)],
                "insight": ["type": ["string", "null"]],
                "invites_user": ["type": "boolean"],
            ],
            "required": ["speaker", "text", "emotion", "look_target", "gesture", "insight", "invites_user"],
            "additionalProperties": false,
        ]

        return try await structured(
            model: fast ? fastModel : model,
            fast: fast,
            instructions: system,
            input: input,
            schemaName: "roundtable_turn",
            schema: schema
        )
    }

    /// One-shot document briefing for "discuss a PDF" mode: a ~300-token
    /// summary plus 3-6 searchable entities for the fresh-facts web search.
    func summarizeDocument(text: String) async throws -> (summary: String, entities: [String]) {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "summary": ["type": "string"],
                "entities": ["type": "array", "items": ["type": "string"]],
            ],
            "required": ["summary", "entities"],
            "additionalProperties": false,
        ]
        let instructions = """
        You prepare briefing notes for a panel of investors about to discuss an uploaded \
        document (usually an investment or pitch deck). Write a tight ~300-token summary: what the \
        document is, the core thesis or ask, the key numbers (market size, revenue, raise, valuation \
        if present), the team, and anything unusual. Then list 3-6 key searchable entities \
        (company names, products, founders, sectors) for a web search on fresh context.
        """
        struct Briefing: Decodable {
            let summary: String
            let entities: [String]
        }
        let briefing: Briefing = try await structured(
            model: fastModel,
            fast: true,
            instructions: instructions,
            input: "DOCUMENT TEXT (may be truncated):\n\(text.prefix(60000))",
            schemaName: "doc_briefing",
            schema: schema
        )
        return (briefing.summary, briefing.entities)
    }

    // MARK: - Shared structured-output request (OpenRouter chat completions)

    private func structured<T: Decodable>(
        model: String,
        fast: Bool,
        instructions: String,
        input: String,
        schemaName: String,
        schema: [String: Any]
    ) async throws -> T {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 1200,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": input],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": schemaName,
                    "strict": true,
                    "schema": schema,
                ],
            ],
        ]
        // fable-5.1 has mandatory reasoning: cap effort low. sonnet-5 allows
        // disabling it entirely — do so on the fast path.
        body["reasoning"] = fast ? ["enabled": false] : ["effort": "low"]

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Secrets.openRouterKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 45

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw ClientError.http(status, String(data: data, encoding: .utf8) ?? "")
        }

        let envelope = try JSONDecoder().decode(ChatEnvelope.self, from: data)
        guard let text = envelope.choices.first?.message.content,
              let jsonData = text.data(using: .utf8) else {
            throw ClientError.emptyOutput
        }
        return try JSONDecoder().decode(T.self, from: jsonData)
    }
}

/// Chat completions envelope (generic functions can't nest types).
private struct ChatEnvelope: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}
