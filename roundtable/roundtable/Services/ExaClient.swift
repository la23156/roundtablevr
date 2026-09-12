//
//  ExaClient.swift
//  roundtable
//
//  Exa web search: fetches a compact fresh-facts block for topical sessions.
//

import Foundation

struct ExaClient {
    /// Returns a prompt-ready block of current context for `topic`, or nil on
    /// any failure/timeout — fresh facts are a bonus, never a blocker.
    func freshFacts(topic: String) async -> String? {
        var request = URLRequest(url: URL(string: "https://api.exa.ai/search")!)
        request.httpMethod = "POST"
        request.setValue(Secrets.exaKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 4
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "query": topic,
            "numResults": 5,
            "type": "auto",
            "contents": ["summary": true],
        ])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        struct Envelope: Decodable {
            struct Result: Decodable {
                let title: String?
                let summary: String?
            }
            let results: [Result]
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              !envelope.results.isEmpty else { return nil }

        let facts = envelope.results.compactMap { r -> String? in
            guard let s = r.summary, !s.isEmpty else { return nil }
            return "- \(r.title ?? "Source"): \(s.prefix(400))"
        }
        guard !facts.isEmpty else { return nil }

        let date = Date.now.formatted(date: .abbreviated, time: .omitted)
        return """
        Fresh context as of \(date) — weave these facts in naturally when relevant; never cite sources or URLs aloud:
        \(facts.joined(separator: "\n"))
        """
    }
}
