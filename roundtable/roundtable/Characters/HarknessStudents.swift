//
//  HarknessStudents.swift
//  roundtable
//
//  The simulated class for HarknessAI teacher training: 8 students with
//  distinct archetypes, reading-comprehension levels, voices, and (recycled)
//  avatar bodies. The flaws are deliberate — they are the obstacles the
//  teacher practices against.
//

import SwiftUI
import UIKit

enum HarknessStudents {
    /// Muted, plausible shirt colors (flat cotton look) — differentiates
    /// students sharing a body without reading as costume glow. Loosely
    /// related to each student's UI tint, several shades desaturated.
    static let shirtColors: [String: UIColor] = [
        "jayden": UIColor(red: 0.48, green: 0.17, blue: 0.19, alpha: 1),  // burgundy
        "sofia": UIColor(red: 0.72, green: 0.55, blue: 0.22, alpha: 1),   // ochre
        "wren": UIColor(red: 0.42, green: 0.41, blue: 0.56, alpha: 1),    // dusty slate
        "tyler": UIColor(red: 0.22, green: 0.38, blue: 0.25, alpha: 1),   // forest
        "maddie": UIColor(red: 0.72, green: 0.5, blue: 0.54, alpha: 1),   // dusty rose
        "amir": UIColor(red: 0.17, green: 0.23, blue: 0.4, alpha: 1),     // navy
        "june": UIColor(red: 0.22, green: 0.42, blue: 0.45, alpha: 1),    // teal slate
        "leo": UIColor(red: 0.65, green: 0.53, blue: 0.38, alpha: 1),     // warm tan
    ]

    /// Archetype by student id (used for scoring: was the Ghost drawn out?).
    static let archetypes: [String: StudentArchetype] = [
        "jayden": .monopolizer,
        "sofia": .tangentWeaver,
        "wren": .ghost,
        "tyler": .confidentlyWrong,
        "maddie": .echo,
        "amir": .solid,
        "june": .solid,
        "leo": .solid,
    ]

    static var ghostID: String? {
        archetypes.first { $0.value == .ghost }?.key
    }
    static var monopolizerID: String? {
        archetypes.first { $0.value == .monopolizer }?.key
    }

    /// The class roster. Voices are validated aura-2 models; avatar bodies
    /// cycle through the five rigged assets (duplicates are cloned at load).
    static func roster(count: Int = 8) -> [CharacterSpec] {
        Array(all.prefix(max(3, min(count, all.count))))
    }

    /// The five students of the scripted tutorial (one per archetype beat).
    static var tutorialCast: [CharacterSpec] {
        TutorialScript.castIDs.compactMap { id in all.first { $0.id == id } }
    }

    static let all: [CharacterSpec] = [
        CharacterSpec(
            id: "jayden",
            name: "Jayden",
            archetype: "The Monopolizer",
            bio: "First hand up, every time. Means well.",
            worldview: StudentArchetype.monopolizer.directorNote
                + " Read the text once, quickly. Confident, friendly, a little oblivious.",
            speechStyle: "Fast, eager, starts with 'Okay so basically—'. Surface-level summaries delivered like breakthroughs.",
            isModerator: false,
            voiceID: "aura-2-draco-en",
            avatarAssetName: "preview",
            tint: .red
        ),
        CharacterSpec(
            id: "sofia",
            name: "Sofia",
            archetype: "The Tangent Weaver",
            bio: "Everything reminds her of something else.",
            worldview: StudentArchetype.tangentWeaver.directorNote
                + " Genuinely curious; the tangents feel connected to her even when they aren't.",
            speechStyle: "Winding, associative — 'wait, this is kind of like…' — drifts from a small detail into a personal story.",
            isModerator: false,
            voiceID: "aura-2-pandora-en",
            avatarAssetName: "avaturn",
            tint: .orange
        ),
        CharacterSpec(
            id: "wren",
            name: "Wren",
            archetype: "The Ghost",
            bio: "Hasn't said a word. Understood everything.",
            worldview: StudentArchetype.ghost.directorNote
                + " Read the text twice and annotated it. Fears being wrong out loud far more than being silent.",
            speechStyle: "Quiet, precise, almost reluctant — but when she speaks it reframes the whole discussion in one or two sentences.",
            isModerator: false,
            voiceID: "aura-2-theia-en",
            avatarAssetName: "brunette",
            tint: .indigo
        ),
        CharacterSpec(
            id: "tyler",
            name: "Tyler",
            archetype: "The Confidently Incorrect",
            bio: "Wrong, loudly, with great charisma.",
            worldview: StudentArchetype.confidentlyWrong.directorNote
                + " Skimmed the text and filled the gaps with vibes. Genuinely believes his misreadings.",
            speechStyle: "Bold declarations — 'no no, the author is CLEARLY saying…' — persuasive tone, shaky facts.",
            isModerator: false,
            voiceID: "aura-2-zeus-en",
            avatarAssetName: "avatarsdk",
            tint: .yellow
        ),
        CharacterSpec(
            id: "maddie",
            name: "Maddie",
            archetype: "The Echo",
            bio: "Strongly agrees with whoever spoke last.",
            worldview: StudentArchetype.echo.directorNote
                + " Participates to participate; hasn't formed her own read yet.",
            speechStyle: "'Yeah, and like—' followed by the previous point in different words, sincerely offered as new.",
            isModerator: false,
            voiceID: "aura-2-luna-en",
            avatarAssetName: "mpfb",
            tint: .pink
        ),
        CharacterSpec(
            id: "amir",
            name: "Amir",
            archetype: "The Builder",
            bio: "Steady, thoughtful, occasionally unsure.",
            worldview: StudentArchetype.solid.directorNote
                + " Read carefully but doubts himself; asks clarifying questions that quietly help everyone.",
            speechStyle: "Measured, hedged — 'I might be wrong, but on the second page…' — cites the text naturally.",
            isModerator: false,
            voiceID: "aura-2-arcas-en",
            avatarAssetName: "preview",
            tint: .teal
        ),
        CharacterSpec(
            id: "june",
            name: "June",
            archetype: "The Challenger",
            bio: "Disagrees politely, and usually for good reason.",
            worldview: StudentArchetype.solid.directorNote
                + " Enjoys productive disagreement; pushes back on Tyler's claims when she can point to the text.",
            speechStyle: "Direct, curious — 'I actually read that differently…' — asks peers real questions.",
            isModerator: false,
            voiceID: "aura-2-aurora-en",
            avatarAssetName: "brunette",
            tint: .green
        ),
        CharacterSpec(
            id: "leo",
            name: "Leo",
            archetype: "The Big-Picture Kid",
            bio: "Wants to know why any of this matters.",
            worldview: StudentArchetype.solid.directorNote
                + " Connects the text to larger stakes; sometimes skips the evidence to get there.",
            speechStyle: "Reflective, zoomed out — 'okay but the real question is…' — occasionally needs pulling back to the page.",
            isModerator: false,
            voiceID: "aura-2-hyperion-en",
            avatarAssetName: "avatarsdk",   // male rig (avaturn is female — voice/body must agree)
            tint: .blue
        ),
    ]
}
