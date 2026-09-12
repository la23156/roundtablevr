//
//  SessionController.swift
//  roundtable
//
//  Owns everything alive during a session: the conversation director, the
//  playback pipeline, gaze tracking, and (later) speech input. Created when
//  the user hits "Enter the Roundtable"; torn down when the space closes.
//

import Foundation
import GroupActivities
import Observation
import PDFKit
import QuartzCore
import RealityKit
import Spatial
import SwiftUI
import UIKit

@MainActor
@Observable
final class SessionController {
    let config: SessionConfig
    private(set) var startedAt: Date?

    /// SharePlay: nil/inactive = solo (everything behaves exactly as before).
    @ObservationIgnored private let coordinator: GroupSessionCoordinator?
    /// True when this controller plays network-fed turns instead of running
    /// the director pipeline.
    let isReplicaSession: Bool
    /// Captured at creation: was this session born under a group session?
    let isGroupSession: Bool

    private var groupActive: Bool { coordinator?.sessionActive == true }
    private var isGroupHost: Bool { groupActive && coordinator?.isHost == true && !isReplicaSession }

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

    /// SharePlay: this participant's template seat pose (replicas sit at a
    /// guest seat, not the space origin) — used for seat-relative UI.
    @ObservationIgnored private(set) var localSeatPose: Pose3D?
    /// SharePlay: card easels for iPhone guests, by participant UUID.
    @ObservationIgnored private var guestCards: [UUID: ParticipantCardEntity] = [:]
    /// SharePlay: positions of the human guest seats (world/space coords).
    @ObservationIgnored private let humanSeats = SeatingLayout.humanPersonaSeats()

    init(config: SessionConfig, coordinator: GroupSessionCoordinator? = nil, replica: Bool = false) {
        self.config = config
        self.coordinator = coordinator
        self.isReplicaSession = replica
        self.isGroupSession = coordinator?.sessionActive == true
        self.director = ConversationDirector(config: config)
        self.playback = PlaybackController(config: config, director: director)
        if replica {
            playback.setReplicaMode()
        }

        // SharePlay host: broadcast the turn pipeline as it happens.
        playback.onTurnPrepared = { [weak self] turn, turnID, epoch, voiceID in
            guard let self, isGroupHost else { return }
            do {
                let payload = try TurnPreparedPayload(turnID: turnID, epoch: epoch,
                                                      voiceID: voiceID, turn: turn)
                coordinator?.send(.turnPrepared(payload))
            } catch {
                print("GROUP turnPrepared encode failed: \(error)")
            }
        }
        playback.onTurnStarted = { [weak self] turnID in
            guard let self, isGroupHost else { return }
            coordinator?.send(.turnStart(turnID: turnID, hostTime: CACurrentMediaTime()))
        }

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

        // SharePlay: guest chairs + card easels, seat-relative fallbacks, and
        // (host) the PDF for everyone via the journal.
        if groupActive {
            await installGuestSeating(handles: handles)
            refreshGuestCards()
            if let pose = coordinator?.systemCoordinator?.localParticipantState.seat?.pose {
                localSeatPose = pose
                gaze.setDefaultHead(SIMD3<Float>(Float(pose.position.x),
                                                 SeatingLayout.seatedEyeHeight + Float(pose.position.y),
                                                 Float(pose.position.z)))
            }
            if isGroupHost {
                Task { [director] in await director.setGuestsPresent(true) }
                if let data = document?.pdf.dataRepresentation() {
                    coordinator?.sharePDF(data)
                }
            }
        }

        await gaze.start()
        wireSpeechInput()
        speech.groupCallActive = groupActive
        await speech.start()
        if groupActive {
            print("SESSION mic backend: \(speech.activeBackend) (group call active)")
        }
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
        if isGroupHost {
            coordinator?.send(.pageChanged(index: newIndex))
        }
    }

    /// SharePlay replica: mirror the host's page flip on the local board.
    func applyRemotePage(index: Int) {
        guard let doc = document, doc.pageCount > 0,
              index != doc.currentPageIndex,
              (0..<doc.pageCount).contains(index) else { return }
        doc.currentPageIndex = index
        refreshBoard()
        glanceAtBoard()
        print("SESSION remote page flip -> \(index + 1)/\(doc.pageCount)")
    }

    /// SharePlay replica: the PDF arrived via the group journal.
    func applyRemoteDocument(data: Data, title: String, pageIndex: Int) {
        guard isReplicaSession, document == nil else { return }
        guard let doc = DiscussionDocument(data: data, title: title) else {
            print("SESSION remote PDF unreadable")
            return
        }
        doc.currentPageIndex = min(max(pageIndex, 0), max(doc.pageCount - 1, 0))
        document = doc
        sceneHandles?.root.findEntity(named: "PresentationBoard")?.isEnabled = true
        refreshBoard()
        print("SESSION remote PDF ready: \(title) (\(doc.pageCount) pages)")
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
        guard !isReplicaSession else { return }   // the host generates turns
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
            if groupActive, let coordinator {
                coordinator.send(.userSpeechStarted(name: coordinator.localName))
            }
            escalationTask?.cancel()
            escalationTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard let self, !Task.isCancelled else { return }
                playback.pauseCurrent()
            }
        }
        speech.onLevel = { [weak self] level in
            guard let self, groupActive else { return }
            coordinator?.sendSpeakingLevel(level)
        }
        speech.onFinal = { [weak self] text in
            guard let self else { return }
            escalationTask?.cancel()
            let words = text.split(separator: " ").count
            guard words >= 2 else {
                discardLocalUtterance()
                return
            }
            // Echo guard: without headphones the mic hears the characters'
            // own speech (AEC can't always cancel it, e.g. simulator on
            // speakers). Discard transcripts that mostly overlap recent lines.
            // It matters even more on the AVCaptureSession fallback path,
            // which has no voice-processing echo cancellation at all.
            if isLikelyEcho(text) {
                print("SESSION echo discarded: \(text.prefix(60))")
                discardLocalUtterance()
                return
            }
            print("SESSION user said: \(text) (facing \(facedAtSpeechOnset ?? "nobody"))")
            userDidInterrupt = true

            if isReplicaSession {
                // Replica: the HOST owns the director. Broadcast the final
                // transcript; the host interrupts + generates the reply and
                // its turnInterrupted/turnPrepared messages do the rest.
                if let coordinator {
                    coordinator.send(.userSpeechFinal(name: coordinator.localName,
                                                      text: text,
                                                      facedCharacterID: facedAtSpeechOnset))
                }
                transcript.append(TranscriptLine(speakerName: "You", text: text, wasInterrupted: false))
                if config.settings.subtitlesEnabled {
                    subtitle = Subtitle(speakerName: "You", text: text, tint: .white)
                }
                return
            }

            Task { [weak self] in
                guard let self else { return }
                _ = await director.bumpEpoch()
                let interruptedTurnID = playback.currentTurnID
                if let fraction = playback.interruptCurrent() {
                    await director.markLastLineInterrupted(spokenFraction: fraction)
                    if case .character(_, let name, let spoken, _) = await director.transcript.last {
                        // Reflect the truncation in the recap transcript too.
                        if let idx = transcript.lastIndex(where: { $0.speakerName == name }) {
                            transcript[idx] = TranscriptLine(speakerName: name, text: spoken, wasInterrupted: true)
                        }
                    }
                    if isGroupHost, let interruptedTurnID {
                        coordinator?.send(.turnInterrupted(turnID: interruptedTurnID,
                                                           spokenFraction: fraction,
                                                           epoch: await director.epoch))
                    }
                }
                let facedName = facedAtSpeechOnset.flatMap { id in config.cast.first { $0.id == id }?.name }
                await director.append(.user(text: text, facing: facedName))
                transcript.append(TranscriptLine(speakerName: "You", text: text, wasInterrupted: false))
                if config.settings.subtitlesEnabled {
                    subtitle = Subtitle(speakerName: "You", text: text, tint: .white)
                }
                if isGroupHost, let coordinator {
                    // Other devices show the host human's line + un-duck.
                    coordinator.send(.userSpeechFinal(name: coordinator.localName,
                                                      text: text,
                                                      facedCharacterID: facedAtSpeechOnset))
                }
                playback.interject(text: text, facedName: facedName)
            }
        }
    }

    /// A local utterance turned out to be noise/echo: resume playback and, in
    /// a group session, tell everyone to un-duck (empty text = false alarm).
    private func discardLocalUtterance() {
        playback.resumeCurrent()
        if groupActive, let coordinator {
            coordinator.send(.userSpeechFinal(name: coordinator.localName, text: "",
                                              facedCharacterID: nil))
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

        // Guest-card glow decay.
        for card in guestCards.values {
            card.update(dt: Float(dt))
        }

        // Moderator closing round at ~80% of the configured session length.
        if !isReplicaSession, !closingRoundTriggered, let started = startedAt,
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

    // MARK: - SharePlay: incoming messages (routed by AppModel)

    func handleGroupMessage(_ message: RTMessage, from participantID: UUID) {
        switch message {
        case .turnPrepared(let payload):
            guard isReplicaSession else { return }
            do {
                let turn = try payload.turn()
                Task { [director] in await director.syncEpoch(to: payload.epoch) }
                playback.enqueueRemote(turn: turn, id: payload.turnID,
                                       voiceID: payload.voiceID, epoch: payload.epoch)
            } catch {
                print("GROUP turnPrepared decode failed: \(error)")
            }

        case .turnStart(let turnID, _):
            guard isReplicaSession else { return }
            playback.playRemote(turnID)

        case .turnInterrupted(_, let fraction, let epoch):
            guard isReplicaSession else { return }
            Task { [weak self] in
                guard let self else { return }
                await director.syncEpoch(to: epoch)
                playback.clearRemoteBuffer()
                if playback.interruptCurrent() != nil,
                   let idx = transcript.lastIndex(where: { $0.speakerName != "You" }) {
                    let line = transcript[idx]
                    let cutoff = max(8, Int(Double(line.text.count) * min(max(fraction, 0), 1)))
                    transcript[idx] = TranscriptLine(speakerName: line.speakerName,
                                                     text: String(line.text.prefix(cutoff)),
                                                     wasInterrupted: true)
                }
                subtitle = nil
            }

        case .userSpeechStarted(let name):
            // A remote human started talking: duck, escalate to pause, glow.
            playback.duck()
            escalationTask?.cancel()
            escalationTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard let self, !Task.isCancelled else { return }
                playback.pauseCurrent()
            }
            print("SESSION remote speech started (\(name))")

        case .userSpeechFinal(let name, let text, let facedID):
            escalationTask?.cancel()
            guard !text.isEmpty else {
                // False alarm on the sender's side: un-duck and carry on.
                playback.resumeCurrent()
                return
            }
            if isGroupHost {
                handleGuestSpeechFinal(name: name, text: text, facedID: facedID,
                                       from: participantID)
            } else {
                // Replica: show the line; the host's turnInterrupted/turn
                // messages handle the actual conversation surgery.
                transcript.append(TranscriptLine(speakerName: name, text: text, wasInterrupted: false))
                if config.settings.subtitlesEnabled {
                    subtitle = Subtitle(speakerName: name, text: text, tint: .cyan)
                }
            }

        case .identity(let identity):
            if isGroupHost {
                Task { [director] in await director.setGuestsPresent(true) }
                if !identity.hasPersona {
                    coordinator?.assignGuestSeat(for: participantID)
                }
            }
            refreshGuestCards()

        case .guestSeats:
            refreshGuestCards()

        case .pageChanged(let index):
            guard isReplicaSession else { return }
            applyRemotePage(index: index)

        case .snapshot(let snapshot):
            // Mid-session snapshots only refresh seat assignments here; the
            // join-time snapshot is consumed by AppModel before this
            // controller exists.
            _ = snapshot
            refreshGuestCards()

        case .sessionEnded:
            break   // AppModel tears the session down
        }
    }

    /// Host: a remote human's interjection — feed the director as a GUEST
    /// line and reply via the fast path, addressing them by name.
    private func handleGuestSpeechFinal(name: String, text: String, facedID: String?,
                                        from participantID: UUID) {
        print("SESSION guest \(name) said: \(text)")
        Task { [weak self] in
            guard let self else { return }
            _ = await director.bumpEpoch()
            let interruptedTurnID = playback.currentTurnID
            if let fraction = playback.interruptCurrent() {
                await director.markLastLineInterrupted(spokenFraction: fraction)
                if case .character(_, let charName, let spoken, _) = await director.transcript.last,
                   let idx = transcript.lastIndex(where: { $0.speakerName == charName }) {
                    transcript[idx] = TranscriptLine(speakerName: charName, text: spoken, wasInterrupted: true)
                }
                if let interruptedTurnID {
                    coordinator?.send(.turnInterrupted(turnID: interruptedTurnID,
                                                       spokenFraction: fraction,
                                                       epoch: await director.epoch))
                }
            }
            let facedName = facedID.flatMap { fid in config.cast.first { $0.id == fid }?.name }
            await director.append(.guest(name: name, text: text, facing: facedName))
            transcript.append(TranscriptLine(speakerName: name, text: text, wasInterrupted: false))
            if config.settings.subtitlesEnabled {
                subtitle = Subtitle(speakerName: name, text: text, tint: .cyan)
            }
            playback.interjectGuest(name: name, text: text, facedName: facedName,
                                    guestPosition: guestHeadPosition(for: participantID))
        }
    }

    /// Where the cast should look when addressing a remote human: live pose
    /// (visionOS 26 Personas) > template seat pose > assigned static slot.
    private func guestHeadPosition(for participantID: UUID) -> SIMD3<Float>? {
        if let states = coordinator?.systemCoordinator?.remoteParticipantStates,
           let state = states.first(where: { $0.key.id == participantID })?.value {
            if let pose = state.pose {
                return SIMD3<Float>(Float(pose.position.x), Float(pose.position.y), Float(pose.position.z))
            }
            if let seat = state.seat {
                return SIMD3<Float>(Float(seat.pose.position.x),
                                    SeatingLayout.seatedEyeHeight,
                                    Float(seat.pose.position.z))
            }
        }
        if let slot = coordinator?.guestSeatSlots[participantID], slot < humanSeats.count {
            return SeatingLayout.headPosition(of: humanSeats[slot])
        }
        return nil
    }

    /// Speaking-level pulses (unreliable channel) light up the guest's card.
    func handleSpeakingLevel(_ level: Float, from participantID: UUID) {
        guestCards[participantID]?.setLevel(level)
    }

    // MARK: - SharePlay: guest chairs + iPhone card easels

    /// Empty chairs at every human guest slot (Personas land on these seats;
    /// iPhone guests get a card easel added on top).
    private func installGuestSeating(handles: RoundtableSceneHandles) async {
        await RoundtableScene.installGuestSeats(in: handles.root, seats: humanSeats)
    }

    /// Sync card easels with the coordinator's iPhone-guest roster.
    private func refreshGuestCards() {
        guard let coordinator, let handles = sceneHandles else { return }
        for (participantID, identity) in coordinator.humans where !identity.hasPersona {
            guard guestCards[participantID] == nil,
                  let slot = coordinator.guestSeatSlots[participantID],
                  slot < humanSeats.count else { continue }
            let seat = humanSeats[slot]
            Task { @MainActor [weak self] in
                let card = await ParticipantCardEntity.make(name: identity.name,
                                                            characterID: identity.characterID)
                guard let self, guestCards[participantID] == nil else { return }
                card.position = seat.position + SIMD3<Float>(0, 0, 0)
                card.orientation = simd_quatf(angle: seat.yaw, axis: [0, 1, 0])
                handles.root.addChild(card)
                guestCards[participantID] = card
                print("SESSION guest card spawned for \(identity.name) at slot \(slot)")
            }
        }
        // Remove cards for departed guests.
        for (participantID, card) in guestCards where coordinator.humans[participantID] == nil {
            card.removeFromParent()
            guestCards[participantID] = nil
        }
    }

    /// Host: catch-up bundle for a late joiner.
    func buildSnapshot() -> SessionSnapshot {
        SessionSnapshot(
            topic: .init(id: config.topic.id, emoji: config.topic.emoji,
                         title: config.topic.title, subtitle: config.topic.subtitle,
                         promptSeed: config.topic.promptSeed),
            castIDs: config.cast.map(\.id),
            settings: .init(sessionMinutes: config.settings.sessionMinutes,
                            paceMultiplier: config.settings.paceMultiplier,
                            subtitlesEnabled: config.settings.subtitlesEnabled),
            transcriptTail: transcript.suffix(20).map {
                .init(speakerName: $0.speakerName, text: $0.text, wasInterrupted: $0.wasInterrupted)
            },
            insights: insights.map {
                .init(title: $0.title, speakerName: $0.speakerName, sparkedByUser: $0.sparkedByUser)
            },
            guestSeats: coordinator?.guestSeatSlots.map {
                GuestSeatAssignment(participantID: $0.key, slot: $0.value)
            } ?? [],
            documentTitle: document?.title,
            documentPageCount: document?.pageCount ?? 0,
            currentPageIndex: document?.currentPageIndex ?? 0)
    }

    /// Replica: seed local state from the host's snapshot (pre-scene).
    func applySnapshot(_ snapshot: SessionSnapshot) {
        transcript = snapshot.transcriptTail.map {
            TranscriptLine(speakerName: $0.speakerName, text: $0.text, wasInterrupted: $0.wasInterrupted)
        }
        insights = snapshot.insights.map {
            Insight(title: $0.title, speakerName: $0.speakerName, sparkedByUser: $0.sparkedByUser)
        }
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
