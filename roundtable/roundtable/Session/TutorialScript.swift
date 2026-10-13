//
//  TutorialScript.swift
//  roundtable
//
//  The interactive HarknessAI tutorial: a curated close reading of Kate
//  Chopin's "The Story of an Hour" (bundled 4-page text on the board) that
//  runs like a real classroom. THE TEACHER LAUNCHES IT: they read one of
//  three catalyst questions aloud (or improvise their own), step back
//  through the opening silence, and the class plays out from their choice —
//  each catalyst branches to a different first realization, and a different
//  post-it is left open at the end as the teacher's handoff.
//
//  Scripted turns ride the replica playback path (enqueueRemote/playRemote),
//  so the web, gem, closeness pulses, deflection tests, stalls, and node
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

/// One way for the teacher to open the seminar. The branch decides which
/// realization the class reaches first.
struct CatalystOption {
    let text: String
    /// Words that identify this option in the teacher's own phrasing.
    let keywords: [String]
    /// 1-based node this opening steers the class toward first.
    let firstNode: Int
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

    // MARK: - Catalysts (the teacher's opening move)

    static let catalysts: [CatalystOption] = [
        CatalystOption(
            text: "What changes in this story — and when, exactly, does it change?",
            keywords: ["change", "changes", "when", "turn", "shift", "moment"],
            firstNode: 1),
        CatalystOption(
            text: "Where does Louise's transformation live — in her mind, or in her body?",
            keywords: ["body", "mind", "physical", "transformation", "live", "pulse", "pulses"],
            firstNode: 2),
        CatalystOption(
            text: "Why does Chopin give us Louise's heart trouble in the very first line?",
            keywords: ["heart", "first", "line", "trouble", "open", "opening", "begin"],
            firstNode: 3),
    ]

    /// Matches the teacher's spoken catalyst to a branch: best keyword
    /// overlap wins; an improvised question falls back to branch 1 (tone).
    static func matchCatalyst(_ spoken: String) -> CatalystOption {
        let tokens = Set(spoken.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 })
        var best = catalysts[0]
        var bestScore = 0
        for option in catalysts {
            let score = option.keywords.filter { tokens.contains($0) }.count
            if score > bestScore {
                best = option
                bestScore = score
            }
        }
        return best
    }

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

    // MARK: - Branch beats (after the teacher's catalyst + opening silence)

    /// Two student turns on page 2 that land the branch's first realization.
    static func branchBeats(firstNode: Int) -> [TutorialBeat] {
        switch firstNode {
        case 2:
            return [
                .closeness(2, 0.6),
                .student(turn("maddie",
                              "Everyone keeps saying she's sad, but the page keeps talking about her body — she 'sank' into the chair, 'pressed down by physical exhaustion.'",
                              emotion: .thoughtful, closestNode: 2, closeness: 0.75)),
                .student(turn("june",
                              "And watch page two: her pulses beat fast, the blood warms every inch of her. Chopin never says 'she changed' — the body announces it before Louise does.",
                              emotion: .passionate, coveredNode: 2)),
            ]
        case 3:
            return [
                .closeness(3, 0.6),
                .student(turn("june",
                              "Line one gives us her weak heart before it even gives us her name. Writers plant what they intend to pay off.",
                              emotion: .thoughtful, closestNode: 3, closeness: 0.75)),
                .student(turn("tyler",
                              "Oh — so the ending can be one sentence, 'the joy that kills,' because line one already loaded the gun. We knew about her heart the whole time.",
                              emotion: .surprised, coveredNode: 3)),
            ]
        default:
            return [
                .closeness(1, 0.6),
                .student(turn("jayden",
                              "Page two is all sparrows and spring and patches of blue sky? Her husband just died. This feels like the wrong weather.",
                              emotion: .surprised, closestNode: 1, closeness: 0.85)),
                .student(turn("june",
                              "That's the move, Jayden. She sits down in grief, and everything through that open window is new spring life. The window flips the story's tone before Louise feels anything.",
                              emotion: .passionate, coveredNode: 1)),
            ]
        }
    }

    /// Wren's silence-breaking realization: body-first change, unless the
    /// branch already covered it (then she lands the window/tone node).
    static func wrenNode(afterFirst firstNode: Int) -> Int {
        firstNode == 2 ? 1 : 2
    }

    static func wrenBeat(node: Int) -> TutorialBeat {
        if node == 1 {
            return .student(turn("wren",
                                 "…Look where she's sitting. The chair faces the open window, and everything through it is spring. The story's weather turns before she does — the window turns the tone.",
                                 emotion: .thoughtful, coveredNode: 1))
        }
        return .student(turn("wren",
                             "…She never says she's changed. Her body says it — her pulses beat fast, the blood warms and relaxes every inch of her. Chopin writes the transformation into the body before Louise can even name it.",
                             emotion: .thoughtful, coveredNode: 2))
    }

    /// Jayden's final-page line that brings the class one question from the
    /// node the teacher will be handed.
    static func closingBeat(openNode: Int) -> TutorialBeat {
        if openNode == 1 {
            return .student(turn("jayden",
                                 "I still don't get the middle, though. She sits down crying, and two paragraphs later she's whispering 'free.' When did the mood even flip?",
                                 emotion: .skeptical, closestNode: 1, closeness: 0.9))
        }
        return .student(turn("jayden",
                             "And then the husband just walks in with his umbrella, and the doctors say joy killed her. Ironic, I guess?",
                             emotion: .skeptical, closestNode: 3, closeness: 0.9))
    }
}

// MARK: - Runner

extension SessionController {
    /// Plays the interactive tutorial: intro -> the teacher's spoken
    /// catalyst -> the step-back silence -> the branch -> the shared spine.
    /// All narrator/student audio synthesizes concurrently up front.
    func runTutorial() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let tts = DeepgramTTSClient()
            let narrator = Entity()
            narrator.position = [0, 1.5, -0.9]
            sceneHandles?.root.addChild(narrator)
            let mouth = CharacterAudio.mouthEntity(on: narrator, headHeight: 0)
            let isTest = ProcessInfo.processInfo.arguments.contains("-tutorialTest")

            var narratorCache: [String: Task<(URL, Double)?, Never>] = [:]
            @MainActor func prewarm(_ text: String) {
                guard narratorCache[text] == nil else { return }
                narratorCache[text] = Task {
                    try? await tts.synthesize(text: text, voiceID: TutorialScript.narratorVoice)
                }
            }
            @MainActor func speak(_ text: String) async {
                prewarm(text)
                guard let (url, duration) = await narratorCache[text]?.value else {
                    print("TUTORIAL narrator synth failed")
                    return
                }
                setTutorSubtitle(text)
                _ = try? await CharacterAudio.play(url: url, on: mouth)
                try? await Task.sleep(for: .seconds(duration + 0.15))
                setTutorSubtitle(nil)
            }

            var studentIDs: [String: UUID] = [:]   // turn text -> id
            @MainActor func prewarmBeats(_ beats: [TutorialBeat]) {
                for beat in beats {
                    switch beat {
                    case .narrator(let text):
                        prewarm(text)
                    case .student(let turn):
                        guard studentIDs[turn.text] == nil else { continue }
                        let voice = config.cast.first { $0.id == turn.speaker }?.voiceID
                            ?? "aura-2-arcas-en"
                        let id = UUID()
                        studentIDs[turn.text] = id
                        playback.enqueueRemote(turn: turn, id: id, voiceID: voice, epoch: 0)
                    default:
                        break
                    }
                }
            }

            @MainActor func run(_ beats: [TutorialBeat]) async {
                for beat in beats {
                    guard sceneHandles != nil else { return }
                    switch beat {
                    case .narrator(let text):
                        await speak(text)
                    case .student(let turn):
                        guard let id = studentIDs[turn.text] else { continue }
                        playback.playRemote(id)
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
                        try? await Task.sleep(for: .seconds(1.6))
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
            }

            let t0 = CACurrentMediaTime()

            // ---- Act 0: the goal, and the teacher's opening move.
            let intro1 = "Welcome to HarknessAI. Your class has read Kate Chopin's Story of an Hour — page one is on the board. Your goal is on the table: three sticky notes, the realizations your students must reach on their own. Turn all three green — without lecturing."
            let intro2 = "A Harkness discussion starts with a catalyst: one complex question with no single right answer. Pick one from the board in front of you — or ask your own — out loud, in your own voice."
            prewarm(intro1); prewarm(intro2)
            // Pre-synthesize every branch's audio now: the teacher's choice
            // then plays instantly whichever way they go.
            for option in TutorialScript.catalysts {
                prewarmBeats(TutorialScript.branchBeats(firstNode: option.firstNode))
                prewarmBeats([TutorialScript.wrenBeat(node: TutorialScript.wrenNode(afterFirst: option.firstNode))])
                let open = openNode(first: option.firstNode)
                prewarmBeats([TutorialScript.closingBeat(openNode: open)])
            }

            await speak(intro1)
            tutorialOverlay?.sweepNotes()
            await speak(intro2)
            tutorialOverlay?.showCatalyst(options: TutorialScript.catalysts.map(\.text))

            // ---- The teacher speaks (or the sim test auto-picks).
            var spokenCatalyst: String?
            onTutorialTeacherSpeech = { text in
                if spokenCatalyst == nil { spokenCatalyst = text }
            }
            if isTest {
                try? await Task.sleep(for: .seconds(6))
                spokenCatalyst = TutorialScript.catalysts[2].text   // branch 3
            } else {
                var waited = 0.0
                while spokenCatalyst == nil {
                    try? await Task.sleep(for: .milliseconds(150)); waited += 0.15
                    if abs(waited - 35) < 0.1 {
                        await speak("Take your time. When you're ready, read one aloud — the room is yours.")
                    }
                }
            }
            onTutorialTeacherSpeech = nil
            let branch = TutorialScript.matchCatalyst(spokenCatalyst ?? "")
            let wren = TutorialScript.wrenNode(afterFirst: branch.firstNode)
            let open = openNode(first: branch.firstNode)
            tutorialOverlay?.hideCatalyst()
            print("TUTORIAL catalyst matched branch \(branch.firstNode): \(spokenCatalyst ?? "")")

            // ---- The step back: ten seconds of silence is a tool.
            let stepBack = "Good. Now the hardest part: lean back, look down at your notes, and say nothing. The silence is what makes a student start."
            await speak(stepBack)
            tutorialBeginOpeningStall()
            var stallWait = 0.0
            while tensionProgress != nil, stallWait < 20 {
                try? await Task.sleep(for: .milliseconds(120)); stallWait += 0.12
            }

            // ---- The branch, then the shared spine.
            var spine: [TutorialBeat] = [
                .page(2),
            ]
            spine += TutorialScript.branchBeats(firstNode: branch.firstNode)
            spine += [
                .narrator("Realization \(branch.firstNode) — your question did that. The sticky note is green and you still haven't told them anything."),
                .page(3),
                .student(TutorialScript.tylerDeflection),
                .narrator("A trap. Answer it and you're lecturing. Hand it back — like this —"),
                .passDeflectionDemo,
                .student(TutorialScript.maddieStall),
                .narrator("Another silence. You know what to do."),
                .awaitStall,
                TutorialScript.wrenBeat(node: wren),
                .narrator("The quiet one — drawn out by silence, not called on. Realization \(wren). Last page."),
                .page(4),
                TutorialScript.closingBeat(openNode: open),
                .narrator("One question away from the last sticky note. Look at it — the note will show you how to ask. In a real class, that landing is yours. Your debrief is waiting."),
            ]
            prewarmBeats(spine)
            await run(spine)

            print(String(format: "TUTORIAL complete in %.0f s (score %d, branch %d)",
                         CACurrentMediaTime() - t0, harknessStats?.score ?? 0, branch.firstNode))
            if isTest {
                harknessOverlayForDebug?.debugRaisePanels = true
                debugPinnedFocus = open - 1   // the handoff note's coaching
            }
        }
    }

    /// The node left for the teacher: 3 unless the branch covered it (then 1).
    private func openNode(first: Int) -> Int {
        first == 3 ? 1 : 3
    }
}

private extension TutorialScript {
    static let tylerDeflection = DirectorTurn(
        speaker: "tyler",
        text: "Okay but 'free, body and soul free' — she's celebrating his death? So she's the villain, right, teacher?",
        emotion: .surprised, lookTarget: "user", gesture: .none, insight: nil,
        invitesUser: true, stallAfter: nil, deflection: true,
        coveredNode: nil, closestNode: nil, nodeCloseness: nil, coachHint: nil)

    static let maddieStall = DirectorTurn(
        speaker: "maddie",
        text: "Yeah it's like what everyone's been saying — she's sort of springtime inside now? If that makes sense.",
        emotion: .thoughtful, lookTarget: "table", gesture: .none, insight: nil,
        invitesUser: false, stallAfter: true, deflection: nil,
        coveredNode: nil, closestNode: nil, nodeCloseness: nil, coachHint: nil)
}
