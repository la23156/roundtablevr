//
//  SessionModels.swift
//  roundtable
//
//  Core value types describing a roundtable session.
//

import SwiftUI

struct SessionSettings: Equatable {
    /// Total session length; the moderator starts the closing round at ~80%.
    var sessionMinutes: Int = 15
    /// Multiplies the beat gap between turns (1.0 = default pacing).
    var paceMultiplier: Double = 1.0
    /// Fetch fresh web context via Exa for topical cards.
    var freshFactsEnabled: Bool = true
    var masterVolume: Double = 1.0
    /// Show the floating subtitle card above the table-edge HUD.
    var subtitlesEnabled: Bool = true
}

struct SessionConfig {
    var topic: TopicCard
    var cast: [CharacterSpec]   // 3...5 members, exactly one isModerator
    var settings: SessionSettings
    /// When set, the session is a "discuss a PDF" seminar: the cast examines
    /// this document (summary + per-page text); the live PDFKit handle lives
    /// on AppModel/SessionController, not here.
    var document: DiscussionDocumentInfo?

    var moderator: CharacterSpec? { cast.first(where: \.isModerator) }
}

struct Insight: Identifiable, Equatable {
    let id = UUID()
    let title: String            // 3-6 word gem label
    let speakerName: String
    let sparkedByUser: Bool
}

struct TranscriptLine: Identifiable {
    let id = UUID()
    let speakerName: String      // "You" for the user
    let text: String
    let wasInterrupted: Bool
}

struct SessionRecap {
    var topicTitle: String
    var insights: [Insight]
    var transcript: [TranscriptLine]
    var durationMinutes: Int
}
