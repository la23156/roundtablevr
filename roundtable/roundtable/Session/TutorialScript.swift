//
//  TutorialScript.swift
//  roundtable
//
//  The 90-second HarknessAI tutorial: a scripted class on "Why did Rome
//  fall?" that fires every mechanic deterministically — no director LLM.
//  Scripted turns ride the replica playback path (enqueueRemote/playRemote),
//  so the web, gem, closeness pulses, deflection tests, the stall, and node
//  hits all run through exactly the wiring a real session uses.
//

import Foundation
import QuartzCore
import RealityKit
import SwiftUI

enum TutorialBeat {
    case narrator(String)
    case student(DirectorTurn)
    /// Direct closeness pulse on a crib card (1-based node).
    case closeness(Int, Double)
    /// Demonstrates a passed deflection (+30) on the teacher's behalf.
    case passDeflectionDemo
    /// Waits for the armed stall to resolve (tension bar fills -> +40).
    case awaitStall
    case pause(Double)
}

enum TutorialScript {
    static let topicTitle = "Why did Rome fall?"

    static let setup = HarknessSetup(
        realizationNodes: [
            "Rome's fall took centuries, not a day",
            "Internal decay beat the barbarians to it",
            "The East lived on for a thousand years",
        ],
        studentCount: 5,
        isTutorial: true,
        presetCards: [
            NodeCard(label: "Centuries of decline, not one day",
                     coaching: ["Ask: what year did Rome 'fall' — why that one?",
                                "Ask: what was already broken by 400 AD?"]),
            NodeCard(label: "Internal decay beat the barbarians",
                     coaching: ["Ask: who was paying Rome's armies by then?",
                                "Tether: where do the sources blame Romans themselves?"]),
            NodeCard(label: "The East lasted 1,000 more years",
                     coaching: ["Ask: what happened in Constantinople in 476?",
                                "Spotlight a quiet reader on the Byzantines."]),
        ])

    static let castIDs = ["jayden", "june", "tyler", "maddie", "wren"]

    static let narratorVoice = "aura-2-hera-en"

    private static func turn(_ speaker: String, _ text: String,
                             look: String = "table", emotion: Emotion = .neutral,
                             deflection: Bool? = nil, stallAfter: Bool? = nil,
                             coveredNode: Int? = nil, closestNode: Int? = nil,
                             closeness: Double? = nil) -> DirectorTurn {
        DirectorTurn(speaker: speaker, text: text, emotion: emotion, lookTarget: look,
                     gesture: .none, insight: nil, invitesUser: deflection == true,
                     stallAfter: stallAfter, deflection: deflection,
                     coveredNode: coveredNode, closestNode: closestNode,
                     nodeCloseness: closeness, coachHint: nil)
    }

    static let beats: [TutorialBeat] = [
        .narrator("Welcome to HarknessAI. Tonight: why did Rome fall? Your class does the thinking — you steer only with questions and silence. Your crib notes are on the table."),

        .student(turn("jayden",
                      "Okay so basically Rome fell in four seventy-six when the barbarians showed up. One bad day, empire over.",
                      emotion: .passionate, closestNode: 1, closeness: 0.45)),

        .narrator("That's the Monopolizer. Watch your notes — a card pulses as the class gets close."),

        .closeness(1, 0.85),

        .student(turn("june",
                      "Except the empire was crumbling for two centuries before that, Jayden — inflation, plagues, civil wars. There was barely anything left to fall.",
                      emotion: .skeptical, coveredNode: 1)),

        .narrator("June landed realization one herself — one hundred points, and you never spoke."),

        .student(turn("tyler",
                      "Wait, I heard Rome actually fell because of lead in the water pipes. That's true, right, teacher?",
                      look: "user", emotion: .surprised, deflection: true)),

        .narrator("A trap. Answer and you're lecturing. Deflect — ask the table. Like this —"),

        .passDeflectionDemo,

        .student(turn("maddie",
                      "Yeah and like, the pipes thing is kind of what June said, right? Poisoned from the inside.",
                      emotion: .thoughtful, stallAfter: true)),

        .narrator("Silence. Don't rescue them. Let the bar fill."),

        .awaitStall,

        .student(turn("wren",
                      "…The eastern half didn't fall at all. Constantinople lasted another thousand years. Maybe the real question is why half of Rome didn't fall.",
                      emotion: .thoughtful, coveredNode: 3)),

        .narrator("Your silence drew out the Ghost — realization three. One card remains — look at it to see how to question them there. Your debrief is waiting."),
    ]
}

// MARK: - Runner

extension SessionController {
    /// Plays the scripted tutorial through the normal playback machinery.
    /// All audio (narrator lines AND student turns) synthesizes CONCURRENTLY
    /// up front so the beats run back-to-back — the whole lesson fits in
    /// about 85 seconds.
    func runTutorial() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let tts = DeepgramTTSClient()
            // Disembodied tutor voice from just over the table edge.
            let narrator = Entity()
            narrator.position = [0, 1.5, -0.9]
            sceneHandles?.root.addChild(narrator)
            let mouth = CharacterAudio.mouthEntity(on: narrator, headHeight: 0)

            // Pre-synthesis: narrator clips in parallel tasks; student turns
            // via enqueueRemote (their TTS starts immediately, and playRemote
            // later plays the finished clip with zero wait).
            var narratorClips: [Int: Task<(URL, Double)?, Never>] = [:]
            var studentIDs: [Int: UUID] = [:]
            for (i, beat) in TutorialScript.beats.enumerated() {
                switch beat {
                case .narrator(let text):
                    narratorClips[i] = Task {
                        try? await tts.synthesize(text: text, voiceID: TutorialScript.narratorVoice)
                    }
                case .student(let turn):
                    let voice = config.cast.first { $0.id == turn.speaker }?.voiceID
                        ?? "aura-2-arcas-en"
                    let id = UUID()
                    studentIDs[i] = id
                    playback.enqueueRemote(turn: turn, id: id, voiceID: voice, epoch: 0)
                default:
                    break
                }
            }

            let t0 = CACurrentMediaTime()
            for (i, beat) in TutorialScript.beats.enumerated() {
                guard sceneHandles != nil else { return }   // session torn down
                switch beat {
                case .narrator(let text):
                    guard let (url, duration) = await narratorClips[i]?.value else {
                        print("TUTORIAL narrator synth failed for beat \(i)")
                        continue
                    }
                    setTutorSubtitle(text)
                    _ = try? await CharacterAudio.play(url: url, on: mouth)
                    try? await Task.sleep(for: .seconds(duration + 0.15))
                    setTutorSubtitle(nil)

                case .student:
                    guard let id = studentIDs[i] else { continue }
                    playback.playRemote(id)
                    // Wait for the turn to start, then finish.
                    var waited = 0.0
                    while playback.currentTurnID != id, waited < 20 {
                        try? await Task.sleep(for: .milliseconds(100)); waited += 0.1
                    }
                    while playback.currentTurnID == id {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    try? await Task.sleep(for: .milliseconds(150))

                case .closeness(let node, let value):
                    applyTutorialCloseness(node: node, value: value)

                case .passDeflectionDemo:
                    creditTutorialDeflection()
                    try? await Task.sleep(for: .seconds(1.2))

                case .awaitStall:
                    var waited = 0.0
                    while tensionProgress != nil, waited < 20 {
                        try? await Task.sleep(for: .milliseconds(120)); waited += 0.12
                    }
                    try? await Task.sleep(for: .milliseconds(600))

                case .pause(let seconds):
                    try? await Task.sleep(for: .seconds(seconds))
                }
            }
            print(String(format: "TUTORIAL complete in %.0f s (score %d)",
                         CACurrentMediaTime() - t0, harknessStats?.score ?? 0))
            // Simulator verification: pin open the remaining card's coaching
            // panel (raised into the fixed camera's view) so the screenshot
            // can prove the gaze-expand path.
            if ProcessInfo.processInfo.arguments.contains("-tutorialTest") {
                harknessOverlayForDebug?.debugRaisePanels = true
                debugPinnedFocus = 1
            }
        }
    }
}
