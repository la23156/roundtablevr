//
//  DeepgramTTSClient.swift
//  roundtable
//
//  Deepgram Aura-2 TTS: text + voice model -> temp MP3. TTFB ~0.2-0.4 s on a
//  warm connection, so whole-turn synthesis is cheap; no chunking needed.
//

import AVFoundation
import Foundation

struct DeepgramTTSClient {
    enum ClientError: LocalizedError {
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .http(let code, let body): return "Deepgram TTS HTTP \(code): \(body.prefix(300))"
            }
        }
    }

    /// Reused session keeps the TLS connection warm across turns.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    /// Synthesizes speech with the given aura-2 voice model, writes a temp
    /// file, and returns it with its playable duration.
    func synthesize(text: String, voiceID: String) async throws -> (url: URL, duration: TimeInterval) {
        var components = URLComponents(string: "https://api.deepgram.com/v1/speak")!
        components.queryItems = [
            URLQueryItem(name: "model", value: voiceID),
            URLQueryItem(name: "encoding", value: "mp3"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Token \(Secrets.deepgramKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])

        let (data, response) = try await Self.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw ClientError.http(status, String(data: data, encoding: .utf8) ?? "")
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tts-\(UUID().uuidString).mp3")
        try data.write(to: url)
        let duration = (try? AVAudioPlayer(contentsOf: url).duration) ?? 0
        return (url, duration)
    }
}
