//
//  TurnModels.swift
//  roundtable
//
//  The director's structured output and the prepared-turn pipeline types.
//

import Foundation

enum Emotion: String, Codable, CaseIterable {
    case neutral, amused, passionate, skeptical, thoughtful, surprised, warm
}

enum Gesture: String, Codable, CaseIterable {
    case none, nod, headShake = "head_shake", leanIn = "lean_in",
         handOpen = "hand_open", chinStroke = "chin_stroke", shrug
}

/// One conversational turn as emitted by the director LLM.
struct DirectorTurn: Codable, Equatable {
    let speaker: String        // cast id
    let text: String
    let emotion: Emotion
    /// Cast id, "user", or "table".
    let lookTarget: String
    let gesture: Gesture
    /// 3-6 word gem label when this turn contains a notable idea, else null.
    let insight: String?
    let invitesUser: Bool

    enum CodingKeys: String, CodingKey {
        case speaker, text, emotion, gesture, insight
        case lookTarget = "look_target"
        case invitesUser = "invites_user"
    }
}

/// A turn with its (progressively synthesized) audio, ready for playback as
/// soon as the first segment exists. `id` is shared across SharePlay devices
/// so the host's turnStart/turnInterrupted messages address the same turn.
struct PreparedTurn {
    let id: UUID
    let turn: DirectorTurn
    let audio: SegmentedTurnAudio
    let epoch: Int
}

/// Entries in the running transcript handed back to the director.
enum TranscriptEntry {
    case character(id: String, name: String, text: String, interrupted: Bool)
    case user(text: String, facing: String?)   // facing = cast id user was looking at
    case guest(name: String, text: String, facing: String?)  // remote SharePlay human
    case note(String)                          // stage note, e.g. a page turn

    var promptLine: String {
        switch self {
        case .character(_, let name, let text, let interrupted):
            return "[\(name.uppercased())]: \(text)\(interrupted ? " (interrupted mid-sentence)" : "")"
        case .user(let text, let facing):
            let f = facing.map { " (facing \($0.capitalized))" } ?? ""
            return "[USER\(f)]: \(text)"
        case .guest(let name, let text, let facing):
            let f = facing.map { " (facing \($0.capitalized))" } ?? ""
            return "[GUEST \(name.uppercased())\(f)]: \(text)"
        case .note(let text):
            return "[NOTE]: \(text)"
        }
    }
}
