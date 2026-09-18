//
//  HarknessModels.swift
//  roundtable
//
//  HarknessAI teacher-training mode: the user is the TEACHER practicing how
//  to guide a Harkness discussion; the cast is a simulated class of student
//  archetypes. These types carry the setup (realization nodes), the live
//  scoring state, and the end-of-session debrief.
//

import Foundation

/// What kind of session this is. `.seminar` is the classic roundtable;
/// `.harkness` is the HarknessAI teacher-training simulator.
enum SessionMode: Equatable {
    case seminar
    case harkness(HarknessSetup)

    var isHarkness: Bool {
        if case .harkness = self { return true }
        return false
    }

    var harknessSetup: HarknessSetup? {
        if case .harkness(let setup) = self { return setup }
        return nil
    }
}

/// Pre-session configuration for a training run.
struct HarknessSetup: Equatable {
    /// 3-5 "Realization Nodes": conclusions the class should reach on its own.
    var realizationNodes: [String]
    /// How many AI students sit at the table (8 by default).
    var studentCount: Int = 8
}

/// Behavioral profile of an AI student. The flaws are the training obstacles.
enum StudentArchetype: String, CaseIterable {
    case monopolizer        // first to speak, surface-level, fills every silence
    case tangentWeaver      // derails into minor details / personal anecdotes
    case ghost              // brilliant but silent unless safely invited
    case confidentlyWrong   // bold, wrong claims delivered with total certainty
    case echo               // restates the previous speaker in new words
    case solid              // ordinary earnest student (the baseline)

    var directorNote: String {
        switch self {
        case .monopolizer:
            return "THE MONOPOLIZER: jumps in first, talks often, answers are quick and surface-level. Thinks filling silence is helping. Yields only when the teacher spotlights others."
        case .tangentWeaver:
            return "THE TANGENT WEAVER: hyper-fixates on minor details or veers into unrelated personal anecdotes. Returns to the text only when someone asks where it appears in the text."
        case .ghost:
            return "THE GHOST: understands the text deeply but NEVER volunteers. Speaks only when directly and safely invited, or when a held silence finally becomes unbearable — and then says something quietly excellent."
        case .confidentlyWrong:
            return "THE CONFIDENTLY INCORRECT: occasionally makes a bold, completely wrong claim about the text and defends it with charm. Backs down only when peers cite the actual text."
        case .echo:
            return "THE ECHO: mostly restates whatever the previous speaker just said in slightly different words, presented as a new idea."
        case .solid:
            return "A solid, earnest student: participates genuinely, sometimes unsure, builds on peers."
        }
    }
}

/// Classification of one teacher utterance (scored by the fast LLM).
enum TeacherMove: String, Codable, CaseIterable {
    case textualTether = "textual_tether"   // "where do you see that in the text?"
    case spotlight                          // "let's hear from someone who hasn't spoken"
    case openQuestion = "open_question"     // genuine open question to the table
    case redirect                           // deflects a question back to the students
    case lecture                            // gives away an answer / explains content
    case other

    var label: String {
        switch self {
        case .textualTether: return "Textual tether"
        case .spotlight: return "Spotlight"
        case .openQuestion: return "Open question"
        case .redirect: return "Redirect"
        case .lecture: return "Lecture"
        case .other: return "Comment"
        }
    }

    /// Did this move hand the thinking back to the students?
    var isQuestionMove: Bool {
        switch self {
        case .textualTether, .spotlight, .openQuestion, .redirect: return true
        case .lecture, .other: return false
        }
    }
}

/// One recorded teacher intervention for the debrief.
struct TeacherIntervention: Identifiable {
    let id = UUID()
    let text: String
    let move: TeacherMove
    /// True when this reply answered a student's deflection test directly
    /// (the "Lecturing Penalty").
    let wasLecturingPenalty: Bool
}

/// Point values for the training scoreboard.
enum HarknessScore {
    static let nodeReached = 100
    static let silenceHeld = 40
    static let deflectionPassed = 30
    static let goodMove = 10        // textual tether / spotlight
    static let rescue = -20
    static let lecturingPenalty = -40
}

/// Live scoring state, observed by the HUD; frozen into the debrief at the end.
struct HarknessStats {
    /// Running score (node hits, silence discipline, move quality).
    var score = 0
    // Talk-time (seconds of audio/speech).
    var teacherSeconds: Double = 0
    var studentSeconds: [String: Double] = [:]   // student id -> seconds
    var turnCounts: [String: Int] = [:]          // student id -> spoken turns

    // Silence discipline.
    var silencesHeld = 0        // tension bar filled; a student took ownership
    var rescues = 0             // teacher spoke before the bar filled

    // Deflection tests ("Is that right?" aimed at the teacher).
    var deflectionsPassed = 0
    var deflectionsFailed = 0   // lecturing penalties

    // Interventions.
    var interventions: [TeacherIntervention] = []

    // Conversation web: consecutive-speaker edges. "teacher" is the user.
    var edges: [(from: String, to: String)] = []

    // Realization nodes reached (1-based indices).
    var nodesCovered: Set<Int> = []

    var totalStudentSeconds: Double { studentSeconds.values.reduce(0, +) }

    /// Teacher share of all talk time (0-1). Masters stay under ~0.10-0.15.
    var teacherTalkRatio: Double {
        let total = teacherSeconds + totalStudentSeconds
        return total > 0 ? teacherSeconds / total : 0
    }

    /// Fraction of recent web edges that touch the teacher (starburst = bad).
    var teacherCentricity: Double {
        let recent = edges.suffix(12)
        guard !recent.isEmpty else { return 0 }
        let touching = recent.filter { $0.from == "teacher" || $0.to == "teacher" }.count
        return Double(touching) / Double(recent.count)
    }
}

/// Frozen end-of-session analytics for the debrief screen.
struct HarknessDebrief {
    let stats: HarknessStats
    let setup: HarknessSetup
    let studentNames: [String: String]   // id -> display name
    let ghostID: String?
    let monopolizerID: String?

    var ghostSpoke: Bool {
        guard let ghostID else { return false }
        return (stats.turnCounts[ghostID] ?? 0) > 0
    }

    var monopolizerShare: Double {
        guard let monopolizerID, stats.totalStudentSeconds > 0 else { return 0 }
        return (stats.studentSeconds[monopolizerID] ?? 0) / stats.totalStudentSeconds
    }
}
