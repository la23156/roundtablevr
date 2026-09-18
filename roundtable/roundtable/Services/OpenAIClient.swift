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
    /// `harkness` adds the training-mode fields (stall/deflection/node).
    func generateTurn(
        system: String,
        input: String,
        castIDs: [String],
        fast: Bool = false,
        harkness: Bool = false
    ) async throws -> DirectorTurn {
        let lookTargets = castIDs + ["user", "table"]
        var properties: [String: Any] = [
            "speaker": ["type": "string", "enum": castIDs],
            "text": ["type": "string"],
            "emotion": ["type": "string", "enum": Emotion.allCases.map(\.rawValue)],
            "look_target": ["type": "string", "enum": lookTargets],
            "gesture": ["type": "string", "enum": Gesture.allCases.map(\.rawValue)],
            "insight": ["type": ["string", "null"]],
            "invites_user": ["type": "boolean"],
        ]
        var required = ["speaker", "text", "emotion", "look_target", "gesture", "insight", "invites_user"]
        if harkness {
            properties["stall_after"] = ["type": "boolean"]
            properties["deflection"] = ["type": "boolean"]
            properties["covered_node"] = ["type": ["integer", "null"]]
            properties["closest_node"] = ["type": ["integer", "null"]]
            properties["node_closeness"] = ["type": "number"]
            properties["coach_hint"] = ["type": ["string", "null"]]
            required += ["stall_after", "deflection", "covered_node",
                         "closest_node", "node_closeness", "coach_hint"]
        }
        let schema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": required,
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

    /// HarknessAI: drafts 3-5 realization nodes for a training run from the
    /// uploaded text. `guidance` is the teacher's optional steer ("focus on
    /// the unreliable narration", "financials only") — empty means the model
    /// picks the richest discussion targets itself.
    func suggestRealizationNodes(documentText: String, guidance: String) async throws -> [String] {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "nodes": [
                    "type": "array",
                    "items": ["type": "string"],
                    "minItems": 3,
                    "maxItems": 5,
                ],
            ],
            "required": ["nodes"],
            "additionalProperties": false,
        ]
        let instructions = """
        You help a teacher prepare a Harkness discussion. From the class text, propose 3-5 \
        "realization nodes": the core conclusions or understandings a class of students should \
        reach BY THEMSELVES through discussion. Good nodes are non-obvious but reachable, arguable \
        from evidence in the text, and specific to THIS text — never generic ("the text has themes"). \
        Write each as one plain sentence a teacher would recognize the moment a student lands on it. \
        Order them in the sequence a discussion would naturally reach them.\
        \(guidance.isEmpty ? "" : "\n\nTHE TEACHER'S STEER (follow it): \(guidance)")
        """
        struct Suggestion: Decodable { let nodes: [String] }
        let suggestion: Suggestion = try await structured(
            model: fastModel,
            fast: true,
            instructions: instructions,
            input: "CLASS TEXT (may be truncated):\n\(documentText.prefix(60000))",
            schemaName: "realization_nodes",
            schema: schema
        )
        return suggestion.nodes
    }

    /// HarknessAI: condenses each realization node into a 3-6 word crib-note
    /// label for the teacher's desk notes (glanceable mid-discussion).
    func condenseNodes(_ nodes: [String]) async throws -> [String] {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "labels": ["type": "array", "items": ["type": "string"]],
            ],
            "required": ["labels"],
            "additionalProperties": false,
        ]
        let instructions = """
        Condense each numbered realization into a 3-6 word crib-note label a teacher can read \
        at a glance mid-discussion. Keep the load-bearing specifics (names, numbers), drop \
        everything else. Return exactly one label per input, in order.
        """
        struct Condensed: Decodable { let labels: [String] }
        let numbered = nodes.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let condensed: Condensed = try await structured(
            model: fastModel,
            fast: true,
            instructions: instructions,
            input: numbered,
            schemaName: "node_labels",
            schema: schema
        )
        guard condensed.labels.count == nodes.count else {
            throw ClientError.emptyOutput
        }
        return condensed.labels
    }

    /// HarknessAI: classifies one teacher utterance into a coaching move.
    /// Runs on the fast model, in parallel with the reply generation — the
    /// result only feeds scoring and the HUD, never blocks the conversation.
    func classifyTeacherMove(text: String, pendingDeflection: Bool) async throws -> TeacherMove {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "move": ["type": "string", "enum": TeacherMove.allCases.map(\.rawValue)],
            ],
            "required": ["move"],
            "additionalProperties": false,
        ]
        let instructions = """
        You score one utterance by a TEACHER practicing Harkness discussion facilitation. \
        Classify it as exactly one move:
        - textual_tether: pushes students back to the text ("where do you see that in the text?").
        - spotlight: invites quieter voices ("let's hear from someone who hasn't spoken yet").
        - open_question: a genuine open question to the table that hands students the thinking.
        - redirect: deflects a student's direct question back to the class instead of answering it.
        - lecture: explains content, gives away an answer, corrects a student directly, or otherwise \
        does the students' thinking for them\(pendingDeflection ? " — especially if it answers the question a student just asked the teacher" : "").
        - other: none of the above (logistics, encouragement, small talk).
        """
        struct Verdict: Decodable { let move: TeacherMove }
        let verdict: Verdict = try await structured(
            model: fastModel,
            fast: true,
            instructions: instructions,
            input: "TEACHER SAID: \"\(text)\"",
            schemaName: "teacher_move",
            schema: schema
        )
        return verdict.move
    }

    /// One-shot document briefing for "discuss a PDF" mode: a ~300-token
    /// summary plus 3-6 searchable entities for the fresh-facts web search.
    /// `forTraining` switches from investor framing to classroom framing
    /// (HarknessAI: the document is a class text, not a pitch deck).
    func summarizeDocument(text: String, forTraining: Bool = false) async throws -> (summary: String, entities: [String]) {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "summary": ["type": "string"],
                "entities": ["type": "array", "items": ["type": "string"]],
            ],
            "required": ["summary", "entities"],
            "additionalProperties": false,
        ]
        let instructions = forTraining ? """
        You prepare a teacher's crib sheet for a class text that a Harkness seminar of students is \
        about to discuss. Write a tight ~300-token summary: what the text is, its central themes and \
        tensions, the key evidence or passages, its genuine ambiguities (the places a good discussion \
        will live), and any common misreadings students might fall into. Then list 3-6 key searchable \
        entities (authors, works, events, concepts) for optional background context.
        """ : """
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
