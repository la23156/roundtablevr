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
    /// Flip the class text on the presentation board to this page (1-based).
    case page(Int)
    /// Direct closeness pulse on a crib card (1-based node).
    case closeness(Int, Double)
    /// Demonstrates a passed deflection (+30) on the teacher's behalf.
    case passDeflectionDemo
    /// Waits for the armed stall to resolve (tension bar fills -> +40).
    case awaitStall
    case pause(Double)
}

enum TutorialScript {
    static let topicTitle = "The Story of an Hour"
    /// Bundled 4-page class text (Kate Chopin, 1894 — public domain),
    /// typeset by tools/make_story_pdf.py; one analytic beat per page.
    static let documentResource = "StoryOfAnHour"

    static let setup = HarknessSetup(
        realizationNodes: [
            "The open window turns the story's tone",
            "Louise's change is written in her body first",
            "The last line was planted in the first",
        ],
        studentCount: 5,
        isTutorial: true,
        presetCards: [
            NodeCard(label: "The window turns the tone",
                     coaching: ["Ask: what does Louise see from the chair?",
                                "Ask: where exactly does the grief scene turn?"]),
            NodeCard(label: "Change hits the body first",
                     coaching: ["Ask: what do her pulses and blood do?",
                                "Tether: find the change before she says 'free'."]),
            NodeCard(label: "Line one loads the last line",
                     coaching: ["Ask: reread line one — why open with her heart?",
                                "Ask: the doctors misread her death. Why can't we?"]),
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
        .narrator("Welcome to HarknessAI. Today your class reads Kate Chopin's Story of an Hour — a thousand words that teach more craft than most novels. Page one is on the board; your crib notes are on the table. Steer only with questions and silence."),

        .student(turn("jayden",
                      "Okay so page one: husband dies in a train crash, wife cries, goes to her room. Standard sad opening, honestly.",
                      emotion: .passionate, closestNode: 3, closeness: 0.3)),

        .student(turn("june",
                      "Except look at the very first line — Chopin gives us the heart trouble before she gives us the husband. Writers don't open with a diagnosis by accident.",
                      emotion: .thoughtful, closestNode: 3, closeness: 0.5)),

        .narrator("They're already reading like writers. Turn the page — and watch your notes."),

        .page(2),
        .closeness(1, 0.85),

        .student(turn("jayden",
                      "Wait, page two is all sparrows and spring and patches of blue sky? Her husband just died. This feels like the wrong weather.",
                      emotion: .surprised, closestNode: 1, closeness: 0.9)),

        .student(turn("june",
                      "That's the move, Jayden. She sits down in grief, and everything through that open window is new spring life. The window flips the story's tone before Louise herself feels anything.",
                      emotion: .passionate, coveredNode: 1)),

        .narrator("Realization one — the setting turns the tone before the character does. A hundred points, and you never spoke."),

        .page(3),

        .student(turn("tyler",
                      "Okay but 'free, body and soul free' — she's celebrating his death? So she's the villain, right, teacher?",
                      look: "user", emotion: .surprised, deflection: true)),

        .narrator("A trap. Answer it and you're lecturing. Hand it back — like this —"),

        .passDeflectionDemo,

        .student(turn("maddie",
                      "Yeah it's like June said with the window thing — she's sort of springtime inside now? If that makes sense.",
                      emotion: .thoughtful, stallAfter: true)),

        .narrator("Silence. Don't rescue them."),

        .awaitStall,

        .student(turn("wren",
                      "…She never says she's changed. Her body says it — her pulses beat fast, the blood warms and relaxes every inch of her. Chopin writes the transformation into the body before Louise can even name it.",
                      emotion: .thoughtful, coveredNode: 2)),

        .narrator("Your silence drew out the Ghost — realization two: write the change into the body before the mind. Last page."),

        .page(4),

        .student(turn("jayden",
                      "And then the husband just walks in with his umbrella, and the doctors say joy killed her. Ironic, I guess?",
                      emotion: .skeptical, closestNode: 3, closeness: 0.9)),

        .narrator("One question away from realization three. Look at that card to see how to ask it — in a real class, the landing is yours. Your debrief is waiting."),
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

                case .page(let number):
                    applyRemotePage(index: number - 1)
                    try? await Task.sleep(for: .seconds(1.6))   // the glance beat

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
                debugPinnedFocus = 2   // the open node-3 card: the handoff
            }
        }
    }
}
