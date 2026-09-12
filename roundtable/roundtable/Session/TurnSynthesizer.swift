//
//  TurnSynthesizer.swift
//  roundtable
//
//  Deepgram generates audio at only ~2x realtime, so waiting for a whole turn
//  costs seconds. Instead: split the text into short clause chunks, synthesize
//  the first one immediately (playback can start after ~1 s), and fill in the
//  rest in the background while earlier chunks play.
//

import Foundation

/// Progressively-filled audio for one turn.
@MainActor
final class SegmentedTurnAudio {
    struct Segment {
        let url: URL
        let duration: TimeInterval
        let text: String
    }

    private(set) var segments: [Segment] = []
    private(set) var isComplete = false
    private(set) var failed = false

    var totalKnownDuration: TimeInterval { segments.reduce(0) { $0 + $1.duration } }

    func append(_ segment: Segment) { segments.append(segment) }
    func finish() { isComplete = true }
    func fail() {
        failed = true
        isComplete = true
    }
}

enum TurnSynthesizer {

    /// Splits text into speakable chunks: sentences, but the FIRST chunk is
    /// capped at ~90 chars (broken at a clause boundary) so time-to-first-audio
    /// stays low; later chunks are whole sentences (fewer prosody seams).
    static func chunks(for text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ".!?…".contains(ch), current.trimmingCharacters(in: .whitespaces).count > 2 {
                sentences.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { sentences.append(tail) }
        guard var first = sentences.first else { return [] }

        // Cap the opening chunk at a clause boundary for fast first audio.
        if first.count > 90 {
            let candidates: [Character] = [",", ";", "—", ":"]
            if let cut = first.prefix(110).lastIndex(where: { candidates.contains($0) }),
               first.distance(from: first.startIndex, to: cut) > 25 {
                let head = String(first[...cut])
                let rest = String(first[first.index(after: cut)...]).trimmingCharacters(in: .whitespaces)
                sentences[0] = head
                if !rest.isEmpty { sentences.insert(rest, at: 1) }
                first = head
            }
        }
        return sentences
    }

    /// Synthesizes the turn: returns once the FIRST chunk is ready (playback
    /// can begin); remaining chunks fill the returned box in the background.
    @MainActor
    static func synthesize(text: String, voiceID: String,
                           tts: DeepgramTTSClient) async throws -> SegmentedTurnAudio {
        let audio = SegmentedTurnAudio()
        let parts = chunks(for: text)
        guard let firstPart = parts.first else {
            audio.finish()
            return audio
        }

        let (url, duration) = try await tts.synthesize(text: firstPart, voiceID: voiceID)
        audio.append(.init(url: url, duration: duration, text: firstPart))

        if parts.count > 1 {
            Task { @MainActor in
                for part in parts.dropFirst() {
                    do {
                        let (url, duration) = try await tts.synthesize(text: part, voiceID: voiceID)
                        audio.append(.init(url: url, duration: duration, text: part))
                    } catch {
                        print("TurnSynthesizer chunk failed: \(error)")
                        audio.fail()
                        return
                    }
                }
                audio.finish()
            }
        } else {
            audio.finish()
        }
        return audio
    }
}
