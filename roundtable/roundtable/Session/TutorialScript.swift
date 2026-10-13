//
//  TutorialScript.swift
//  roundtable
//
//  The HarknessAI tutorial as a CONVERSATION-GUIDE GAME on Kate Chopin's
//  "The Story of an Hour" (bundled 4-page text on the board).
//
//  The loop the player learns:
//    1. The Tutor briefs the intention: three realizations the students
//       must reach on their own (each post-it flashes as it's named).
//    2. A board shows suggested lines; THE CLASS WAITS until the teacher
//       says one aloud (or their own version) — every advance is gated on
//       the teacher's real voice.
//    3. A matching line earns a soft chime (+points); the students take
//       the steer and land the realization; the post-it turns green.
//
//  Scripted turns ride the replica playback path, so the web, gem,
//  closeness pulses, and node hits run through the real session wiring.
//

import Foundation
import QuartzCore
import RealityKit
import SwiftUI

/// One gated moment: the teacher must say something matching `keywords`
/// before the class moves.
struct GuideGate {
    /// What the moment needs ("They've noticed the weather…").
    let title: String
    /// Suggested lines shown on the board.
    let suggestions: [String]
    /// A spoken line counts if it contains ANY of these (lowercased).
    let keywords: [String]
    /// Tutor's hint after a couple of near-misses.
    let nudge: String
}

enum TutorialScript {
    static let topicTitle = "The Story of an Hour"
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
                     coaching: ["Ask: what is Louise's body doing?",
                                "Tether: find the change before she says 'free'."]),
            NodeCard(label: "Line one loads the last line",
                     coaching: ["Ask: why open with her heart trouble?",
                                "Ask: the doctors misread the ending. Why can't we?"]),
        ])

    static let castIDs = ["jayden", "june", "tyler", "maddie", "wren"]
    static let narratorVoice = "aura-2-hera-en"

    // MARK: - The gates (the player's moves)

    static let launchGate = GuideGate(
        title: "Launch the discussion with a catalyst — one open question, no right answer.",
        suggestions: [
            "What changes in this story — and when, exactly?",
            "Why does Chopin give us Louise's heart trouble in the very first line?",
        ],
        keywords: [],   // any real question launches a class
        nudge: "Any open question works — read one off the board, in your own words if you like.")

    static let windowGate = GuideGate(
        title: "They've noticed the weather — but not what it's doing to the story. Steer them to the window.",
        suggestions: [
            "What does Louise actually see from that chair?",
            "Where exactly does the mood of the story turn?",
        ],
        keywords: ["see", "sees", "chair", "window", "mood", "turn", "turns",
                   "outside", "looking", "spring", "feel", "shift"],
        nudge: "Point them at what she sees — the chair faces an open window.")

    static let deflectGate = GuideGate(
        title: "Tyler just asked YOU. Don't answer — hand the question back to the table.",
        suggestions: [
            "I don't know — what does the table think?",
            "Where in the text do you see that?",
        ],
        keywords: ["table", "think", "thinks", "text", "where", "class",
                   "everyone", "else", "others", "you all", "anyone"],
        nudge: "Never answer a deflection. Ask the table what they think.")

    static let bodyGate = GuideGate(
        title: "They're circling her feelings — but Chopin hid the change somewhere specific. Send them to her body.",
        suggestions: [
            "What is Louise's body doing in this scene?",
            "Can you find the change before she ever says 'free'?",
        ],
        keywords: ["body", "physical", "pulse", "pulses", "blood", "hands",
                   "breath", "skin", "doing", "physically"],
        nudge: "Her pulses, her blood — ask what her body is doing.")

    static let plantGate = GuideGate(
        title: "Last note. The ending only works because of page one. Send them back to the first line.",
        suggestions: [
            "Why did Chopin tell us about her heart in the very first line?",
            "Reread the first sentence — what did it promise?",
        ],
        keywords: ["first", "heart", "beginning", "start", "opening",
                   "sentence", "line", "promise", "promised", "back"],
        nudge: "Send them back to the very first sentence of the story.")

    // MARK: - Student lines

    static func turn(_ speaker: String, _ text: String, look: String = "table",
                     emotion: Emotion = .neutral, deflection: Bool? = nil,
                     coveredNode: Int? = nil, closestNode: Int? = nil,
                     closeness: Double? = nil) -> DirectorTurn {
        DirectorTurn(speaker: speaker, text: text, emotion: emotion, lookTarget: look,
                     gesture: .none, insight: nil, invitesUser: deflection == true,
                     stallAfter: nil, deflection: deflection,
                     coveredNode: coveredNode, closestNode: closestNode,
                     nodeCloseness: closeness, coachHint: nil)
    }

    /// Every scripted student turn, in play order (pre-synthesized up front).
    static let openerJayden = turn(
        "jayden",
        "Okay so, husband dies in a train crash, wife cries, goes upstairs. Pretty standard sad story so far, honestly.",
        emotion: .passionate, closestNode: 1, closeness: 0.3)

    static let weatherJayden = turn(
        "jayden",
        "Page two is weird though — sparrows, spring, patches of blue sky? Her husband just died. It's the wrong weather.",
        emotion: .surprised, closestNode: 1, closeness: 0.6)

    static let windowJune = turn(
        "june",
        "Wait — that's it. She's facing the open window, and everything through it is new spring life. The story's whole mood turns right there, before Louise herself feels anything. The window changes the tone.",
        emotion: .passionate, coveredNode: 1)

    static let tylerDeflection = turn(
        "tyler",
        "Okay but page three — 'free, body and soul free'? She's celebrating his death. So she's the villain, right, teacher?",
        look: "user", emotion: .surprised, deflection: true)

    static let maddieCircling = turn(
        "maddie",
        "I don't think she's a villain, she's just like… feeling a lot of feelings? It's confusing what she even feels.",
        emotion: .thoughtful, closestNode: 2, closeness: 0.5)

    static let wrenBody = turn(
        "wren",
        "…Her body answers before she does. Her pulses beat fast, the blood warms and relaxes every inch of her. Chopin writes the change into Louise's body before Louise can even name it. She's not deciding to be free — she's discovering she already is.",
        emotion: .thoughtful, coveredNode: 2)

    static let endingJayden = turn(
        "jayden",
        "And then the husband just walks in with his umbrella and she drops dead. The doctors say 'the joy that kills.' Ironic, I guess?",
        emotion: .skeptical, closestNode: 3, closeness: 0.7)

    static let plantJune = turn(
        "june",
        "Oh — the first line. 'Afflicted with a heart trouble.' The doctors misread her death, but we can't, because Chopin loaded that sentence before anything happened. The ending was planted in the opening.",
        emotion: .passionate, coveredNode: 3)

    static var allStudentTurns: [DirectorTurn] {
        [openerJayden, weatherJayden, windowJune, tylerDeflection,
         maddieCircling, wrenBody, endingJayden, plantJune]
    }
}

// MARK: - Runner

extension SessionController {
    /// Runs the conversation-guide game. Every act: students talk, the board
    /// shows the teacher's move, the class WAITS for their voice, a chime
    /// confirms the steer, the realization lands, the post-it goes green.
    func runTutorial() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let tts = DeepgramTTSClient()
            let narrator = Entity()
            narrator.position = [0, 1.5, -0.9]
            sceneHandles?.root.addChild(narrator)
            let mouth = CharacterAudio.mouthEntity(on: narrator, headHeight: 0)
            let chimeURL = Bundle.main.url(forResource: "success_chime", withExtension: "wav")
            let isTest = ProcessInfo.processInfo.arguments.contains("-tutorialTest")

            // ---- Concurrent pre-synthesis of every line in the lesson.
            var narratorCache: [String: Task<(URL, Double)?, Never>] = [:]
            @MainActor func prewarm(_ text: String, delay: Double = 0) {
                guard narratorCache[text] == nil else { return }
                narratorCache[text] = Task {
                    // Staggered + one retry: ~18 clips synthesize up front and
                    // Deepgram 429s a simultaneous burst.
                    if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                    if let clip = try? await tts.synthesize(text: text, voiceID: TutorialScript.narratorVoice) {
                        return clip
                    }
                    try? await Task.sleep(for: .seconds(2))
                    return try? await tts.synthesize(text: text, voiceID: TutorialScript.narratorVoice)
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
            // Narrator lines synthesize concurrently while the first plays.
            for line in Array([
                "Welcome to HarknessAI. Tonight your class discusses Kate Chopin's Story of an Hour — page one is on the board, and they've all done the reading.",
                "Here is your intention. By the end, the students should discover three things on their own.",
                "One: the open window turns the story's tone.",
                "Two: Louise's change is written in her body before her mind.",
                "Three: the famous last line was planted in the very first.",
                "You never say these aloud — your art is asking the question that lets a student arrive. A note pulses as they get close, and turns green when they land it. When a board like this appears, it's your turn to speak.",
                "Good. Now lean back and say nothing — silence is what makes a student start.",
                "Note one is green — they found it, and all you did was ask.",
                "That was Wren — the quiet one. The right question reaches students who never volunteer. Note two is green.",
                "All three notes are green — and every realization came out of a student's mouth, not yours. That is a Harkness class. Leave the table when you're ready; your debrief is waiting.",
            ]).enumerated() {
                prewarm(line.element, delay: Double(line.offset) * 0.4)
            }
            var studentIDs: [String: UUID] = [:]
            @MainActor func enqueue(_ turn: DirectorTurn, after delay: Double) -> UUID {
                let voice = config.cast.first { $0.id == turn.speaker }?.voiceID ?? "aura-2-arcas-en"
                let id = UUID()
                studentIDs[turn.text] = id
                Task { @MainActor [weak self] in
                    if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                    self?.playback.enqueueRemote(turn: turn, id: id, voiceID: voice, epoch: 0)
                }
                return id
            }
            for (i, turn) in TutorialScript.allStudentTurns.enumerated() {
                _ = enqueue(turn, after: 1.0 + Double(i) * 0.4)
            }
            @MainActor func play(_ turn: DirectorTurn) async {
                guard var id = studentIDs[turn.text] else { return }
                for attempt in 0..<2 {
                    playback.playRemote(id)
                    var waited = 0.0
                    while playback.currentTurnID != id, waited < 20 {
                        try? await Task.sleep(for: .milliseconds(100)); waited += 0.1
                    }
                    if playback.currentTurnID == id { break }
                    // Synthesis was dropped (rate limit): re-enqueue and retry.
                    guard attempt == 0 else { return }
                    print("TUTORIAL re-enqueueing dropped turn [\(turn.speaker)]")
                    id = enqueue(turn, after: 0)
                }
                while playback.currentTurnID == id {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
            @MainActor func chime() async {
                if let chimeURL {
                    _ = try? await CharacterAudio.play(url: chimeURL, on: mouth)
                }
            }

            // ---- The gate: show the move, wait for the teacher's voice.
            var latestUtterance: String?
            onTutorialTeacherSpeech = { text in latestUtterance = text }
            @MainActor func awaitGate(_ gate: GuideGate, testLine: String,
                                      points: Int? = nil, flash: String? = nil) async {
                tutorialOverlay?.showGuide(title: gate.title, options: gate.suggestions)
                latestUtterance = nil
                var misses = 0
                var waitedSinceHint = 0.0
                if isTest {
                    try? await Task.sleep(for: .seconds(4))
                    latestUtterance = testLine
                }
                while true {
                    guard let heard = latestUtterance else {
                        try? await Task.sleep(for: .milliseconds(150))
                        waitedSinceHint += 0.15
                        if waitedSinceHint > 45 {
                            waitedSinceHint = 0
                            await speak(gate.nudge)
                        }
                        continue
                    }
                    latestUtterance = nil
                    let lowered = " " + heard.lowercased() + " "
                    let matched = gate.keywords.isEmpty
                        ? heard.split(separator: " ").count >= 4
                        : gate.keywords.contains { lowered.contains($0) }
                    if matched { break }
                    misses += 1
                    if misses % 2 == 0 {
                        await speak(gate.nudge)
                        waitedSinceHint = 0
                    }
                }
                tutorialOverlay?.hideGuide()
                await chime()
                if let points {
                    awardTutorialPoints(points, flash: flash ?? "Good move +\(points)")
                }
                try? await Task.sleep(for: .milliseconds(400))
            }

            let t0 = CACurrentMediaTime()

            // ================= ACT 0 — the briefing =================
            await speak("Welcome to HarknessAI. Tonight your class discusses Kate Chopin's Story of an Hour — page one is on the board, and they've all done the reading.")
            await speak("Here is your intention. By the end, the students should discover three things on their own.")
            tutorialOverlay?.flashNote(1)
            await speak("One: the open window turns the story's tone.")
            tutorialOverlay?.flashNote(2)
            await speak("Two: Louise's change is written in her body before her mind.")
            tutorialOverlay?.flashNote(3)
            await speak("Three: the famous last line was planted in the very first.")
            await speak("You never say these aloud — your art is asking the question that lets a student arrive. A note pulses as they get close, and turns green when they land it. When a board like this appears, it's your turn to speak.")

            // ================= ACT 1 — the launch =================
            await awaitGate(TutorialScript.launchGate,
                            testLine: "What changes in this story and when exactly does it change?")
            await speak("Good. Now lean back and say nothing — silence is what makes a student start.")
            tutorialBeginOpeningStall()
            let rescuesBefore = harknessStats?.rescues ?? 0
            var stallWait = 0.0
            while tensionProgress != nil, stallWait < 20 {
                try? await Task.sleep(for: .milliseconds(120)); stallWait += 0.12
            }
            if (harknessStats?.rescues ?? 0) > rescuesBefore {
                await speak("You rescued them — in this room, silence is your sharpest tool. Once more: quiet, and let it stretch.")
                tutorialBeginOpeningStall()
                stallWait = 0
                while tensionProgress != nil, stallWait < 20 {
                    try? await Task.sleep(for: .milliseconds(120)); stallWait += 0.12
                }
            }
            await play(TutorialScript.openerJayden)

            // ================= ACT 2 — the window (note 1) =================
            applyRemotePage(index: 1)
            try? await Task.sleep(for: .seconds(1.4))
            await play(TutorialScript.weatherJayden)
            await awaitGate(TutorialScript.windowGate,
                            testLine: "What does Louise actually see from that chair?",
                            points: HarknessScore.goodMove, flash: "Good steer +\(HarknessScore.goodMove)")
            await play(TutorialScript.windowJune)
            await speak("Note one is green — they found it, and all you did was ask.")

            // ================= ACT 3 — the deflection + the body (note 2) =================
            applyRemotePage(index: 2)
            try? await Task.sleep(for: .seconds(1.4))
            await play(TutorialScript.tylerDeflection)
            await awaitGate(TutorialScript.deflectGate,
                            testLine: "I don't know, what does the table think?")
            creditTutorialDeflection()
            await play(TutorialScript.maddieCircling)
            await awaitGate(TutorialScript.bodyGate,
                            testLine: "What is Louise's body doing in this scene?",
                            points: HarknessScore.goodMove, flash: "Good steer +\(HarknessScore.goodMove)")
            await play(TutorialScript.wrenBody)
            await speak("That was Wren — the quiet one. The right question reaches students who never volunteer. Note two is green.")

            // ================= ACT 4 — the plant (note 3) =================
            applyRemotePage(index: 3)
            try? await Task.sleep(for: .seconds(1.4))
            await play(TutorialScript.endingJayden)
            await awaitGate(TutorialScript.plantGate,
                            testLine: "Why did Chopin tell us about her heart in the very first line?",
                            points: HarknessScore.goodMove, flash: "Good steer +\(HarknessScore.goodMove)")
            await play(TutorialScript.plantJune)
            await chime()
            await speak("All three notes are green — and every realization came out of a student's mouth, not yours. That is a Harkness class. Leave the table when you're ready; your debrief is waiting.")

            onTutorialTeacherSpeech = nil
            print(String(format: "TUTORIAL complete in %.0f s (score %d)",
                         CACurrentMediaTime() - t0, harknessStats?.score ?? 0))
        }
    }
}
