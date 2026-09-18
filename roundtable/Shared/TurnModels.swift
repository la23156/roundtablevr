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

    // HarknessAI training mode only (absent -> nil in classic seminars).
    /// The room goes dead quiet after this line; the teacher's silence
    /// discipline is being tested (tension meter).
    var stallAfter: Bool?
    /// This line is a deflection test: the student turns to the TEACHER and
    /// asks them directly ("Is that right?"). Answering it = lecturing.
    var deflection: Bool?
    /// 1-based realization-node index the class just organically reached.
    var coveredNode: Int?
    /// 1-based index of the UNCOVERED node the thread is currently nearest.
    var closestNode: Int?
    /// 0-1: how close the discussion is to landing closestNode (drives the
    /// pulse on the teacher's desk notes).
    var nodeCloseness: Double?
    /// Short coaching whisper for the teacher when a specific move would
    /// work right now ("Wren knows this — spotlight her"), else null.
    var coachHint: String?

    enum CodingKeys: String, CodingKey {
        case speaker, text, emotion, gesture, insight, deflection
        case lookTarget = "look_target"
        case invitesUser = "invites_user"
        case stallAfter = "stall_after"
        case coveredNode = "covered_node"
        case closestNode = "closest_node"
        case nodeCloseness = "node_closeness"
        case coachHint = "coach_hint"
    }

    init(speaker: String, text: String, emotion: Emotion, lookTarget: String,
         gesture: Gesture, insight: String?, invitesUser: Bool,
         stallAfter: Bool? = nil, deflection: Bool? = nil, coveredNode: Int? = nil,
         closestNode: Int? = nil, nodeCloseness: Double? = nil, coachHint: String? = nil) {
        self.speaker = speaker
        self.text = text
        self.emotion = emotion
        self.lookTarget = lookTarget
        self.gesture = gesture
        self.insight = insight
        self.invitesUser = invitesUser
        self.stallAfter = stallAfter
        self.deflection = deflection
        self.coveredNode = coveredNode
        self.closestNode = closestNode
        self.nodeCloseness = nodeCloseness
        self.coachHint = coachHint
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speaker = try c.decode(String.self, forKey: .speaker)
        text = try c.decode(String.self, forKey: .text)
        emotion = try c.decode(Emotion.self, forKey: .emotion)
        lookTarget = try c.decode(String.self, forKey: .lookTarget)
        gesture = try c.decode(Gesture.self, forKey: .gesture)
        insight = try c.decodeIfPresent(String.self, forKey: .insight)
        invitesUser = try c.decode(Bool.self, forKey: .invitesUser)
        stallAfter = try c.decodeIfPresent(Bool.self, forKey: .stallAfter)
        deflection = try c.decodeIfPresent(Bool.self, forKey: .deflection)
        coveredNode = try c.decodeIfPresent(Int.self, forKey: .coveredNode)
        closestNode = try c.decodeIfPresent(Int.self, forKey: .closestNode)
        nodeCloseness = try c.decodeIfPresent(Double.self, forKey: .nodeCloseness)
        coachHint = try c.decodeIfPresent(String.self, forKey: .coachHint)
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
