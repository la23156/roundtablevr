//
//  SessionController.swift
//  roundtable
//
//  Owns everything alive during a session: the conversation director, the
//  playback pipeline, gaze tracking, and (later) speech input. Created when
//  the user hits "Enter the Roundtable"; torn down when the space closes.
//

import Foundation
import Observation
import QuartzCore
import RealityKit
import SwiftUI
import UIKit

@MainActor
@Observable
final class SessionController {
    let config: SessionConfig
    private(set) var startedAt: Date?

    /// Set by ImmersiveView once the scene is built; entry point for all
    /// entity-level work (avatars, gem, audio) in later phases.
    @ObservationIgnored var sceneHandles: RoundtableSceneHandles?

    /// Live PDF for "discuss a PDF" sessions (assigned by AppModel before
    /// prefetchOpening; the value-type snapshot rides in `config.document`).
    var document: DiscussionDocument?

    @ObservationIgnored let director: ConversationDirector
    @ObservationIgnored private(set) var playback: PlaybackController!
    @ObservationIgnored let gaze = GazeTracker()
    @ObservationIgnored private let speech = SpeechInput()
    @ObservationIgnored private var escalationTask: Task<Void, Never>?
    @ObservationIgnored private var userDidInterrupt = false
    @ObservationIgnored private var facedAtSpeechOnset: String?

    /// Insights collected so far (game layer fills this from director turns).
    private(set) var insights: [Insight] = []
    private(set) var transcript: [TranscriptLine] = []

    /// Current subtitle line (nil = hidden). Observed by the subtitle attachment.
    struct Subtitle: Equatable {
        let speakerName: String
        let text: String
        let tint: Color
    }
    private(set) var subtitle: Subtitle?

    /// Characters that recently acknowledged the user's gaze (cooldowns).
    @ObservationIgnored private var lastAcknowledged: [String: Double] = [:]
    @ObservationIgnored private var faceStart: (id: String, since: Double)?

    init(config: SessionConfig) {
        self.config = config
        self.director = ConversationDirector(config: config)
        self.playback = PlaybackController(config: config, director: director)

        playback.userHead = { [weak self] in
            self?.gaze.headPosition ?? SIMD3<Float>(0, 1.2, 0)
        }
        playback.onTranscriptLine = { [weak self] turn in
            guard let self else { return }
            let name = config.cast.first { $0.id == turn.speaker }?.name ?? turn.speaker
            transcript.append(TranscriptLine(speakerName: name, text: turn.text, wasInterrupted: false))
        }
        playback.onTurnStart = { [weak self] turn in
            guard let self, config.settings.subtitlesEnabled,
                  let spec = config.cast.first(where: { $0.id == turn.speaker }) else { return }
            subtitle = Subtitle(speakerName: spec.name, text: turn.text, tint: spec.tint)
        }
        playback.onTurnEnd = { [weak self] in
            self?.subtitle = nil
        }
        playback.onInsight = { [weak self] turn in
            guard let self, let title = turn.insight else { return }
            let name = config.cast.first { $0.id == turn.speaker }?.name ?? turn.speaker
            // The current line was appended just before this callback; if the
            // one before it is the user's, they sparked this insight.
            let sparkedByUser = transcript.dropLast().last?.speakerName == "You"
            insights.append(Insight(title: title, speakerName: name, sparkedByUser: sparkedByUser))
            spawnInsightGem(from: turn.speaker, golden: sparkedByUser)
        }
    }

    /// A little gem materializes over the speaker and arcs onto the rack.
    private func spawnInsightGem(from speakerID: String, golden: Bool) {
        guard let handles = sceneHandles,
              let speaker = playback.character(for: speakerID) else { return }

        var material = PhysicallyBasedMaterial()
        let color: UIColor = golden
            ? UIColor(red: 1.0, green: 0.82, blue: 0.25, alpha: 1)
            : UIColor(red: 0.15, green: 0.95, blue: 0.45, alpha: 1)
        material.baseColor = .init(tint: color)
        material.emissiveColor = .init(color: color)
        material.emissiveIntensity = 1.8
        material.roughness = .init(floatLiteral: 0.15)

        let gem = ModelEntity(mesh: .generateBox(size: 0.05, cornerRadius: 0.006), materials: [material])
        gem.orientation = simd_quatf(angle: .pi / 4, axis: normalize(SIMD3<Float>(1, 0, 1)))
        handles.root.addChild(gem)

        let start = speaker.headWorldPosition + SIMD3<Float>(0, 0.55, 0)
        let slot = Float(insights.count - 1)
        let rackWorld = handles.gemRack.convert(position: [min(-0.21 + slot * 0.07, 0.21), 0.05, 0], to: nil)
        gem.position = start

        Task { @MainActor in
            let steps = 70
            for i in 0...steps {
                let t = Float(i) / Float(steps)
                let eased = t * t * (3 - 2 * t)
                var p = mix(start, rackWorld, t: SIMD3<Float>(repeating: eased))
                p.y += sinf(t * .pi) * 0.45   // arc over the table
                gem.position = p
                gem.orientation = simd_quatf(angle: Float(i) * 0.09, axis: [0, 1, 0])
                    * simd_quatf(angle: .pi / 4, axis: normalize(SIMD3<Float>(1, 0, 1)))
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    /// Builds cast avatars into the scene and starts the conversation.
    func beginSession(handles: RoundtableSceneHandles) async {
        sceneHandles = handles
        startedAt = .now

        // Load avatars (replacing gray-box placeholders) and register them.
        for spec in config.cast {
            guard let anchor = handles.characterAnchors[spec.id],
                  let seat = handles.seats[spec.id] else { continue }
            do {
                let avatar = try await AvatarLoader.load(assetName: spec.avatarAssetName)
                anchor.findEntity(named: "Placeholder")?.removeFromParent()
                if let ibl = handles.root.findEntity(named: "IBLSource") {
                    avatar.root.forEachDescendantIncludingSelf { e in
                        if e.components.has(ModelComponent.self) {
                            e.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
                        }
                    }
                }
                let character = CharacterEntity(spec: spec, seat: seat, anchor: anchor, avatar: avatar)
                playback.register(character)
                gaze.characterHeads[spec.id] = character.headWorldPosition
                let bounds = avatar.root.visualBounds(relativeTo: nil)
                print("SESSION avatar \(spec.id)=\(spec.avatarAssetName) extents=\(bounds.extents) joints=\(character.debugJointNames.count) legJoints=\(character.debugJointNames.filter { $0.contains("UpLeg") || $0.hasSuffix("Leg") }.map { $0.split(separator: "/").last! })")
            } catch {
                print("Avatar load failed for \(spec.id): \(error)")
            }
        }

        // Put the current page up on the presentation board.
        if document != nil {
            refreshBoard()
        }

        await gaze.start()
        wireSpeechInput()
        await speech.start()
        playback.startPlaying()

        // -pdfTest verification hook: the simulator can't click the HUD, so
        // flip to page 2 automatically after 25 s to exercise the reaction path.
        if ProcessInfo.processInfo.arguments.contains("-pdfTest"), document != nil {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(25))
                self?.changePage(delta: 1)
            }
        }
    }

    // MARK: - Document mode (presentation board + page flips)

    /// HUD prev/next: shows the new page on the board, updates the director's
    /// page context, notes the turn in the transcript, and has the table react.
    func changePage(delta: Int) {
        guard let doc = document, doc.pageCount > 0 else { return }
        let newIndex = max(0, min(doc.pageCount - 1, doc.currentPageIndex + delta))
        guard newIndex != doc.currentPageIndex else { return }
        doc.currentPageIndex = newIndex
        refreshBoard()

        let pageNumber = newIndex + 1
        let pageText = doc.pageTexts.indices.contains(newIndex) ? doc.pageTexts[newIndex] : ""
        print("SESSION page flip -> \(pageNumber)/\(doc.pageCount)")
        Task { [director] in
            await director.updateCurrentPage(index: newIndex, text: pageText)
            await director.append(.note("The user turned to page \(pageNumber) of \(doc.pageCount)."))
        }
        playback.queueDirective("The user just turned the presentation to page \(pageNumber). The next speaker glances at the board, briefly acknowledges the new page, and reacts to its actual content.")
        glanceAtBoard()
    }

    /// Re-renders the current page as a texture on the wall board.
    private func refreshBoard() {
        guard let doc = document, let handles = sceneHandles else { return }
        let index = doc.currentPageIndex
        Task { @MainActor in
            guard let image = doc.pageImage(index, width: 1600) else {
                print("SESSION board render failed for page \(index + 1)")
                return
            }
            await RoundtableScene.setBoardImage(image, in: handles.root)
        }
    }

    /// Everyone glances at the board for a beat, then returns to the speaker.
    private func glanceAtBoard() {
        guard let handles = sceneHandles,
              let board = handles.root.findEntity(named: "PresentationBoard") else { return }
        let target = board.position(relativeTo: nil)
        for spec in config.cast {
            playback.character(for: spec.id)?.lookTarget = target
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            if let speakerID = playback.currentSpeakerID,
               let speaker = playback.character(for: speakerID) {
                for spec in config.cast where spec.id != speakerID {
                    playback.character(for: spec.id)?.lookTarget = speaker.headWorldPosition
                }
                speaker.lookTarget = gaze.headPosition
            } else {
                for spec in config.cast {
                    playback.character(for: spec.id)?.lookTarget = gaze.headPosition
                }
            }
        }
    }

    /// Called from the menu the moment the user taps Enter: fresh facts kick
    /// off concurrently and the first turns generate while the room loads.
    func prefetchOpening() {
        if config.settings.freshFactsEnabled {
            // Document sessions search on the deck's extracted entities;
            // topic sessions keep the original topic-title query.
            let query: String?
            if let doc = config.document {
                query = doc.entities.isEmpty ? doc.title : doc.entities.joined(separator: ", ")
            } else if config.topic.wantsFreshFacts {
                query = config.topic.title
            } else {
                query = nil
            }
            if let query {
                Task { [director] in
                    let facts = await ExaClient().freshFacts(topic: query)
                    await director.setFreshFacts(facts)
                }
            }
        }
        if let doc = config.document {
            playback.queueDirective("Session start: the moderator welcomes the table, introduces the uploaded document \"\(doc.title)\" — page 1 is up on the presentation board — and invites first impressions of the deck.")
        }
        playback.startGenerating()
    }

    /// Interjection flow: duck on speech onset; if the user keeps talking for
    /// 700 ms, hard-pause; a substantial final transcript confirms the
    /// interruption (truncate the line, bump the epoch, regenerate); a
    /// throwaway transcript resumes playback as if nothing happened.
    private func wireSpeechInput() {
        speech.onSpeechStart = { [weak self] in
            guard let self else { return }
            facedAtSpeechOnset = gaze.facedCharacterID
            userDidInterrupt = false
            playback.duck()
            escalationTask?.cancel()
            escalationTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard let self, !Task.isCancelled else { return }
                playback.pauseCurrent()
            }
        }
        speech.onFinal = { [weak self] text in
            guard let self else { return }
            escalationTask?.cancel()
            let words = text.split(separator: " ").count
            guard words >= 2 else {
                playback.resumeCurrent()
                return
            }
            // Echo guard: without headphones the mic hears the characters'
            // own speech (AEC can't always cancel it, e.g. simulator on
            // speakers). Discard transcripts that mostly overlap recent lines.
            if isLikelyEcho(text) {
                print("SESSION echo discarded: \(text.prefix(60))")
                playback.resumeCurrent()
                return
            }
            print("SESSION user said: \(text) (facing \(facedAtSpeechOnset ?? "nobody"))")
            userDidInterrupt = true
            Task { [weak self] in
                guard let self else { return }
                _ = await director.bumpEpoch()
                if let fraction = playback.interruptCurrent() {
                    await director.markLastLineInterrupted(spokenFraction: fraction)
                    if case .character(_, let name, let spoken, _) = await director.transcript.last {
                        // Reflect the truncation in the recap transcript too.
                        if let idx = transcript.lastIndex(where: { $0.speakerName == name }) {
                            transcript[idx] = TranscriptLine(speakerName: name, text: spoken, wasInterrupted: true)
                        }
                    }
                }
                let facedName = facedAtSpeechOnset.flatMap { id in config.cast.first { $0.id == id }?.name }
                await director.append(.user(text: text, facing: facedName))
                transcript.append(TranscriptLine(speakerName: "You", text: text, wasInterrupted: false))
                if config.settings.subtitlesEnabled {
                    subtitle = Subtitle(speakerName: "You", text: text, tint: .white)
                }
                playback.interject(text: text, facedName: facedName)
            }
        }
    }

    /// True when `text` mostly repeats one of the last few character lines —
    /// i.e. the mic heard the app's own audio, not the user.
    private func isLikelyEcho(_ text: String) -> Bool {
        func tokens(_ s: String) -> Set<String> {
            Set(s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
        }
        let heard = tokens(text)
        guard !heard.isEmpty else { return true }
        for line in transcript.suffix(3) where line.speakerName != "You" {
            let spoken = tokens(line.text)
            guard !spoken.isEmpty else { continue }
            let overlap = Double(heard.intersection(spoken).count) / Double(heard.count)
            if overlap > 0.45 { return true }
        }
        return false
    }

    @ObservationIgnored private var closingRoundTriggered = false

    /// Per-frame: playback tick + gaze-acknowledgment behavior.
    func tick(time: Double, dt: Double) {
        playback.tick(time: time, dt: dt)

        // Moderator closing round at ~80% of the configured session length.
        if !closingRoundTriggered, let started = startedAt,
           Date.now.timeIntervalSince(started) > Double(config.settings.sessionMinutes) * 60 * 0.8 {
            closingRoundTriggered = true
            let moderator = config.moderator?.name ?? "The moderator"
            playback.queueDirective("Closing round: \(moderator) notes the hour is nearly up and asks each character for one final thought, one at a time. After the last one, \(moderator) warmly asks the USER for theirs.")
        }

        // A non-speaking character the user faces for >0.8 s glances back
        // (10 s per-character cooldown).
        if let faced = gaze.facedCharacterID, faced != playback.currentSpeakerID {
            if faceStart?.id != faced {
                faceStart = (faced, time)
            } else if let start = faceStart, time - start.since > 0.8,
                      time - (lastAcknowledged[faced] ?? -100) > 10,
                      let character = playback.character(for: faced) {
                lastAcknowledged[faced] = time
                character.lookTarget = gaze.headPosition
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1.6))
                    guard let self else { return }
                    if playback.currentSpeakerID != faced,
                       let speakerID = playback.currentSpeakerID,
                       let speaker = playback.character(for: speakerID) {
                        character.lookTarget = speaker.headWorldPosition
                    }
                }
            }
        } else {
            faceStart = nil
        }
    }

    func sessionDidBecomeActive() {
        guard startedAt == nil else { return }
        startedAt = .now
    }

    func buildRecap() -> SessionRecap {
        let minutes = startedAt.map { Int(Date.now.timeIntervalSince($0) / 60) } ?? 0
        return SessionRecap(
            topicTitle: config.topic.title,
            insights: insights,
            transcript: transcript,
            durationMinutes: max(minutes, insights.isEmpty && transcript.isEmpty ? 0 : 1)
        )
    }

    func teardown() {
        escalationTask?.cancel()
        speech.stop()
        playback.stopAll()
        gaze.stop()
    }
}
