//
//  TopicDeck.swift
//  roundtable
//
//  Topic cards the user picks from in the menu.
//

import Foundation

struct TopicCard: Identifiable, Equatable {
    let id: String
    let emoji: String
    let title: String
    let subtitle: String
    /// Seed handed to the director alongside the title to frame the discussion.
    let promptSeed: String
    /// Pull fresh web context via Exa before the session starts.
    let wantsFreshFacts: Bool

    static func custom(_ text: String) -> TopicCard {
        TopicCard(
            id: "custom",
            emoji: "✍️",
            title: text,
            subtitle: "Your own topic",
            promptSeed: "The user chose this topic themselves; take it seriously and explore it from several angles.",
            wantsFreshFacts: true
        )
    }
}

enum TopicDeck {
    static let presets: [TopicCard] = [
        TopicCard(
            id: "aliens",
            emoji: "👽",
            title: "Do aliens exist?",
            subtitle: "Fermi paradox, odds, and what contact would mean",
            promptSeed: "Cover the Fermi paradox, the Drake equation, recent exoplanet findings, and what first contact would do to society.",
            wantsFreshFacts: true
        ),
        TopicCard(
            id: "ai-soul",
            emoji: "🤖",
            title: "Could an AI ever have a soul?",
            subtitle: "Minds, consciousness, and what makes someone someone",
            promptSeed: "Debate machine consciousness, the hard problem, functionalism vs. embodiment, and whether it matters morally.",
            wantsFreshFacts: true
        ),
        TopicCard(
            id: "simulation",
            emoji: "🕹️",
            title: "Are we living in a simulation?",
            subtitle: "Bostrom's argument and its critics",
            promptSeed: "Take Bostrom's trilemma seriously, then attack it. What evidence could ever settle it?",
            wantsFreshFacts: false
        ),
        TopicCard(
            id: "money-evil",
            emoji: "💰",
            title: "Is money the root of all evil?",
            subtitle: "Greed, incentives, and human nature",
            promptSeed: "Argue over whether money corrupts or merely reveals, incentive design, and historical alternatives to markets.",
            wantsFreshFacts: false
        ),
        TopicCard(
            id: "free-will",
            emoji: "🎲",
            title: "Is free will an illusion?",
            subtitle: "Determinism, choice, and responsibility",
            promptSeed: "Determinism vs. libertarian free will vs. compatibilism, neuroscience of decisions, and what it means for blame and praise.",
            wantsFreshFacts: false
        ),
        TopicCard(
            id: "mars",
            emoji: "🚀",
            title: "Should we colonize Mars?",
            subtitle: "Backup planet or expensive distraction?",
            promptSeed: "Weigh planetary backup arguments against fix-Earth-first arguments; bring in current mission progress.",
            wantsFreshFacts: true
        ),
        TopicCard(
            id: "best-decade",
            emoji: "📻",
            title: "What was the best decade in history?",
            subtitle: "Nostalgia on trial",
            promptSeed: "Each character should champion a different era and defend it with real history — music, tech, politics, daily life.",
            wantsFreshFacts: false
        ),
        TopicCard(
            id: "art",
            emoji: "🎨",
            title: "What makes art, art?",
            subtitle: "Beauty, intention, and bananas taped to walls",
            promptSeed: "Institutional theory vs. beauty vs. intention; discuss famous provocations and whether AI images count.",
            wantsFreshFacts: false
        ),
    ]
}
