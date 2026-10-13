//
//  PlaybackController.swift
//  roundtable
//
//  Runs the conversation: keeps a 2-turn lookahead buffer (turn text + TTS
//  audio), plays turns spatially with lip sync, moves the gem, and
//  choreographs everyone's gazes. Epoch checks make interruption cheap:
//  anything stale simply discards itself.
//

import Foundation
import QuartzCore
import RealityKit

@MainActor
final class PlaybackController {
    private let config: SessionConfig
    private let director: ConversationDirector
    private let tts = DeepgramTTSClient()
    private let lipSync = LipSyncDriver()
    let gem = SpeakingGem()

    private var characters: [String: CharacterEntity] = [:]
    private var orderedCast: [CharacterEntity] { config.cast.compactMap { characters[$0.id] } }

    private var buffer: [PreparedTurn] = []
    private var fillTask: Task<Void, Never>?
    private var playing = false
    private(set) var currentSpeakerID: String?
    private var currentPlayback: AudioPlaybackController?
    private var gapTask: Task<Void, Never>?

    // Interruption state
    private var currentTurnStartedAt: Double = 0
    private var currentTurnDuration: Double = 0
    private var pausedAt: Double?
    /// Identity of the segment currently playing; a watchdog captures it and
    /// only acts if it's still current (i.e. completion never fired).
    private var currentSegmentToken = UUID()

    // Latency instrumentation + fast-path flag for the reply after an interjection.
    private var interjectedAt: Double?
    private var nextTurnIsFast = false

    /// Set by SessionController: called when a turn carries an insight.
    var onInsight: ((DirectorTurn) -> Void)?
    var onTranscriptLine: ((DirectorTurn) -> Void)?
    /// Fired when a turn's audio starts (drives subtitles).
    var onTurnStart: ((DirectorTurn) -> Void)?
    /// Fired when a turn's audio fully finishes (subtitle fade-out).
    var onTurnEnd: (() -> Void)?

    // MARK: SharePlay hooks (host broadcasts; replicas are fed externally)

    /// Host: the director LLM just returned a turn (fires BEFORE TTS so
    /// replicas can start synthesizing in parallel with the host).
    var onTurnPrepared: ((DirectorTurn, UUID, Int, String) -> Void)?
    /// Host: playback of this turn just started.
    var onTurnStarted: ((UUID) -> Void)?
    /// Replica mode: no local fill loop; the buffer is fed by the network.
    private(set) var isReplica = false
    /// ID of the turn currently playing (for turnInterrupted broadcasts).
    private(set) var currentTurnID: UUID?
    /// Replica: prepared turns waiting for the host's turnStart.
    private var remotePrepared: [UUID: PreparedTurn] = [:]
    /// Replica: a turnStart that arrived before synthesis finished.
    private var pendingRemoteStartID: UUID?

    func setReplicaMode() { isReplica = true }

    /// User head position provider for look-at (falls back to seated origin).
    var userHead: () -> SIMD3<Float> = { SIMD3<Float>(0, 1.2, 0) }

    // MARK: HarknessAI training mode

    /// Fired when a turn marked stall_after finishes: the room goes quiet and
    /// the teacher's silence discipline is tested. Playback does NOT schedule
    /// the next turn until resumeAfterStall / interject.
    var onStall: (() -> Void)?
    /// True while a stall is holding the floor open.
    private(set) var stalled = false
    private var currentTurnStalls = false
    /// Debug (-harknessTest): force the next played turn to stall so the
    /// tension-meter loop can be verified deterministically in the simulator.
    var debugForceStallNextTurn = false
    private var isHarkness: Bool { config.mode.isHarkness }

    private var nextDirective: String

    private var steadyStateDirective: String {
        config.mode.isHarkness
            ? "The teacher is silent. The students continue among themselves — build on, question, or push back against what was just said, true to each archetype."
            : "The user is listening silently; continue the discussion naturally between characters. Build on or push back against the last point."
    }

    init(config: SessionConfig, director: ConversationDirector) {
        self.config = config
        self.director = director
        self.nextDirective = config.mode.isHarkness
            ? "Session start: the class has just settled with the text in front of them. The teacher hasn't spoken. One student (not the Ghost) opens with a first impression of the text."
            : "Session start: the moderator opens with one warm line welcoming the table, then poses tonight's question."
    }

    func register(_ character: CharacterEntity) {
        characters[character.spec.id] = character
    }

    func character(for id: String) -> CharacterEntity? { characters[id] }

    // MARK: - Conversation loop

    /// Begin generating turns (no scene needed) — called the moment the user
    /// taps "Enter the Roundtable" so audio is ready when the room appears.
    func startGenerating() {
        guard !isReplica else { return }   // replicas play network-fed turns
        guard fillTask == nil else { return }
        fillTask = Task { [weak self] in
            await self?.fillLoop()
        }
    }

    /// Begin playing buffered turns — called once the cast is in the scene.
    func startPlaying() {
        startGenerating()
        idleGazes()
        playNextWhenReady(afterGap: 0.2)
    }

    func stopAll() {
        fillTask?.cancel()
        gapTask?.cancel()
        currentPlayback?.stop()
        lipSync.stop()
        buffer.removeAll()
        playing = false
    }

    private func fillLoop() async {
        while !Task.isCancelled {
            if buffer.count >= 2 {
                try? await Task.sleep(for: .milliseconds(50))
                continue
            }
            do {
                let directive = nextDirective
                let fast = nextTurnIsFast
                nextTurnIsFast = false
                nextDirective = steadyStateDirective
                let llmStart = CACurrentMediaTime()
                guard let (turn, epoch) = try await director.generateNextTurn(directive: directive, fast: fast) else { continue }
                let llmDone = CACurrentMediaTime()
                let voice = config.cast.first { $0.id == turn.speaker }?.voiceID ?? config.cast[0].voiceID
                let turnID = UUID()
                // SharePlay: replicas get the text NOW so their local TTS runs
                // in parallel with ours (audio bytes never cross the wire).
                onTurnPrepared?(turn, turnID, epoch, voice)
                // Returns as soon as the FIRST chunk is synthesized; the rest
                // fills in while earlier chunks play.
                let audio = try await TurnSynthesizer.synthesize(text: turn.text, voiceID: voice, tts: tts)
                let ttsDone = CACurrentMediaTime()
                print(String(format: "SESSION-LAT turn[%@]%@ llm=%.2fs tts-first-chunk=%.2fs",
                             turn.speaker, fast ? " (fast)" : "", llmDone - llmStart, ttsDone - llmDone))
                let current = await director.epoch
                guard epoch == current else { continue }
                buffer.append(PreparedTurn(id: turnID, turn: turn, audio: audio, epoch: epoch))
            } catch {
                if Task.isCancelled || error is CancellationError { return }
                print("fillLoop error: \(error)")
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func playNextWhenReady(afterGap gap: TimeInterval) {
        gapTask?.cancel()
        gapTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(gap))
            while let self, !Task.isCancelled {
                if let next = self.buffer.first {
                    self.buffer.removeFirst()
                    let currentEpoch = await self.director.epoch
                    if next.epoch == currentEpoch {
                        self.play(next)
                        return
                    }
                } else {
                    try? await Task.sleep(for: .milliseconds(40))
                }
            }
        }
    }

    private func play(_ prepared: PreparedTurn) {
        guard let speaker = characters[prepared.turn.speaker] else {
            playNextWhenReady(afterGap: 0.2)
            return
        }
        playing = true
        stalled = false
        currentTurnStalls = isHarkness && (prepared.turn.stallAfter == true || debugForceStallNextTurn)
        if debugForceStallNextTurn {
            debugForceStallNextTurn = false
            print("HARKNESS debug: forcing stall after this turn")
        }
        currentSpeakerID = speaker.spec.id
        currentTurnID = prepared.id
        onTurnStarted?(prepared.id)
        if let t0 = interjectedAt {
            interjectedAt = nil
            print(String(format: "SESSION-LAT end-of-speech -> reply audio: %.2fs", CACurrentMediaTime() - t0))
        }
        print("SESSION turn [\(prepared.turn.speaker)]: \(prepared.turn.text)")
        onTranscriptLine?(prepared.turn)
        if prepared.turn.insight != nil { onInsight?(prepared.turn) }

        gem.attach(to: speaker)
        choreographGazes(speaker: speaker, turn: prepared.turn)
        currentTurnStartedAt = CACurrentMediaTime()
        // Defensive: make sure this speaker isn't carrying a stale duck.
        unduck()
        onTurnStart?(prepared.turn)
        playSegment(0, of: prepared, on: speaker)
    }

    /// Plays segment `index`, chaining to the next as background synthesis
    /// fills the box; a short poll bridges any synthesis gap.
    private func playSegment(_ index: Int, of prepared: PreparedTurn, on speaker: CharacterEntity) {
        Task { @MainActor in
            // Wait for the segment if synthesis hasn't caught up yet.
            while index >= prepared.audio.segments.count {
                let currentEpoch = await director.epoch
                if prepared.audio.isComplete || prepared.epoch != currentEpoch {
                    turnFinished()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            let currentEpoch = await director.epoch
            guard playing, prepared.epoch == currentEpoch else { return }
            let segment = prepared.audio.segments[index]
            currentTurnDuration = prepared.audio.totalKnownDuration
            do {
                let controller = try await CharacterAudio.play(url: segment.url, on: speaker.mouth)
                currentPlayback = controller
                lipSync.speak(
                    track: VisemeMapper.track(for: segment.text, duration: segment.duration),
                    avatar: speaker.avatar
                )
                let token = UUID()
                currentSegmentToken = token
                controller.completionHandler = { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self, self.playing, self.currentSegmentToken == token else { return }
                        self.advanceSegment(after: index, of: prepared, on: speaker)
                    }
                }
                // Watchdog: AudioPlaybackController's completion doesn't fire in
                // some environments (notably the simulator); advance on the
                // clip's known duration if the callback never arrives.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(segment.duration + 1.5))
                    guard let self, self.playing, self.pausedAt == nil,
                          self.currentSegmentToken == token else { return }
                    let currentEpoch = await self.director.epoch
                    guard self.playing, prepared.epoch == currentEpoch,
                          self.currentSegmentToken == token else { return }
                    print("SESSION watchdog advanced past segment \(index) of [\(prepared.turn.speaker)]")
                    self.advanceSegment(after: index, of: prepared, on: speaker)
                }
            } catch {
                print("play error: \(error)")
                turnFinished()
            }
        }
    }

    /// Shared continuation for completion callback + watchdog: next segment,
    /// or finish the turn when the last known segment has played.
    private func advanceSegment(after index: Int, of prepared: PreparedTurn, on speaker: CharacterEntity) {
        if prepared.audio.isComplete, index + 1 >= prepared.audio.segments.count {
            turnFinished()
        } else {
            playSegment(index + 1, of: prepared, on: speaker)
        }
    }

    private func turnFinished() {
        playing = false
        currentSpeakerID = nil
        currentTurnID = nil
        onTurnEnd?()
        lipSync.stop()
        gem.attach(to: nil)
        idleGazes()
        if currentTurnStalls {
            // HarknessAI: the room goes dead quiet. Nobody speaks until the
            // tension resolves (SessionController owns the timer) or the
            // teacher breaks the silence. Checked BEFORE the replica guard:
            // the scripted tutorial feeds turns through the replica path.
            currentTurnStalls = false
            stalled = true
            onStall?()
            return
        }
        guard !isReplica else { return }   // the host's turnStart drives replicas
        let gap = Double.random(in: 0.3...1.0) * config.settings.paceMultiplier
        playNextWhenReady(afterGap: gap)
    }

    /// HarknessAI: the stall resolved WITHOUT the teacher speaking — the
    /// discomfort finally forced a student to take ownership of the lull.
    /// Buffered turns predate the silence, so they're discarded and the next
    /// turn is generated against the outcome.
    func resumeAfterStall(directive: String) {
        guard stalled else { return }
        stalled = false
        buffer.removeAll()
        fillTask?.cancel()
        fillTask = nil
        nextDirective = directive
        startGenerating()
        playNextWhenReady(afterGap: 0.2)
    }

    // MARK: - Replica feed (SharePlay: turns arrive from the host)

    /// A turnPrepared message arrived: synthesize the audio locally and hold
    /// the turn until the host's turnStart (which may already be waiting).
    func enqueueRemote(turn: DirectorTurn, id: UUID, voiceID: String, epoch: Int) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let audio = try await TurnSynthesizer.synthesize(text: turn.text, voiceID: voiceID, tts: tts)
                let current = await director.epoch
                guard epoch >= current else { return }   // stale: interrupted since
                let prepared = PreparedTurn(id: id, turn: turn, audio: audio, epoch: epoch)
                remotePrepared[id] = prepared
                if pendingRemoteStartID == id {
                    pendingRemoteStartID = nil
                    playRemote(id)
                }
            } catch {
                print("SESSION replica synth failed for turn \(id): \(error)")
            }
        }
    }

    /// The host started playing this turn: play our local synthesis of it.
    func playRemote(_ id: UUID) {
        guard let prepared = remotePrepared.removeValue(forKey: id) else {
            pendingRemoteStartID = id   // synthesis still running; play when ready
            return
        }
        pendingRemoteStartID = nil
        gapTask?.cancel()
        if playing { _ = interruptCurrent() }
        play(prepared)
    }

    /// Drop buffered remote turns (a human interjected; new epoch incoming).
    func clearRemoteBuffer() {
        remotePrepared.removeAll()
        pendingRemoteStartID = nil
        buffer.removeAll()
    }

    // MARK: - Interruption (driven by SessionController)

    /// Lower the current speaker's voice while the user starts talking.
    func duck() {
        setSpeakerGain(-18)
    }

    func unduck() {
        setSpeakerGain(0)
    }

    private func setSpeakerGain(_ decibels: Double) {
        guard let id = currentSpeakerID, let speaker = characters[id],
              var spatial = speaker.mouth.components[SpatialAudioComponent.self] else { return }
        spatial.gain = Audio.Decibel(decibels)
        speaker.mouth.components.set(spatial)
    }

    /// Hard-pause the current clip (user kept talking). Reversible.
    func pauseCurrent() {
        guard playing, pausedAt == nil else { return }
        pausedAt = CACurrentMediaTime()
        currentPlayback?.pause()
    }

    /// False positive: resume the paused clip and restore gain.
    func resumeCurrent() {
        guard let paused = pausedAt else {
            unduck()
            return
        }
        pausedAt = nil
        lipSync.shiftClock(by: CACurrentMediaTime() - paused)
        currentPlayback?.play()
        unduck()
    }

    /// Confirmed interruption: kill the clip; returns how much of the line had
    /// been spoken (0-1) so the transcript can be truncated to match.
    func interruptCurrent() -> Double? {
        guard playing else { return nil }
        let elapsed = (pausedAt ?? CACurrentMediaTime()) - currentTurnStartedAt
        let fraction = currentTurnDuration > 0 ? min(max(elapsed / currentTurnDuration, 0), 1) : 1
        pausedAt = nil
        // Un-duck BEFORE clearing currentSpeakerID: setSpeakerGain resolves the
        // mouth entity through it, so the old order left the character stuck
        // at -18 dB for every later turn (the "quiet voices" bug).
        unduck()
        currentPlayback?.stop()
        currentPlayback = nil
        lipSync.stop()
        gem.attach(to: nil)
        playing = false
        currentSpeakerID = nil
        currentTurnID = nil
        gapTask?.cancel()
        return fraction
    }

    /// The user said something: everyone reacts, the addressed (or most
    /// relevant) character answers first, and stale prepared turns are gone.
    func interject(text: String, facedName: String?) {
        stalled = false
        buffer.removeAll()
        interjectedAt = CACurrentMediaTime()
        nextTurnIsFast = true
        // Abort any stale in-flight generation so the reply starts NOW
        // instead of after the doomed request completes.
        fillTask?.cancel()
        fillTask = nil
        if isHarkness {
            let facing = facedName.map { " while looking at \($0)" } ?? ""
            nextDirective = """
            The TEACHER just said\(facing): "\(text)". Respond as the class per the RESPOND TO THE \
            TEACHER'S MOVES rules: a textual tether kills the tangent and sends everyone to the page; \
            a spotlight brings out a quiet student (the Ghost, if it feels safe); an open question gets \
            taken up between students; a lecture deflates the room. If the teacher addressed a specific \
            student, that student reacts first.
            """
        } else if let facedName {
            nextDirective = "The user just spoke directly to \(facedName) (they were facing them): \"\(text)\". \(facedName) responds first, addressing the user as 'you'. Others may chime in after."
        } else {
            nextDirective = "The user just said: \"\(text)\". Whoever is most relevant responds first, addressing the user directly as 'you'."
        }
        // Everyone turns to the user for a beat — someone at the table spoke.
        for character in orderedCast {
            character.lookTarget = userHead()
        }
        startGenerating()
        playNextWhenReady(afterGap: 0.05)
    }

    /// A remote SharePlay human said something (host only): same treatment as
    /// a local interjection, but the cast addresses the guest by name and
    /// turns toward their seat.
    func interjectGuest(name: String, text: String, facedName: String?,
                        guestPosition: SIMD3<Float>?) {
        buffer.removeAll()
        interjectedAt = CACurrentMediaTime()
        nextTurnIsFast = true
        fillTask?.cancel()
        fillTask = nil
        if let facedName {
            nextDirective = "\(name), a human guest at the table, just spoke directly to \(facedName): \"\(text)\". \(facedName) responds first, addressing \(name) by name. Others may chime in after."
        } else {
            nextDirective = "\(name), a human guest at the table, just said: \"\(text)\". Whoever is most relevant responds first, addressing \(name) by name."
        }
        let look = guestPosition ?? userHead()
        for character in orderedCast {
            character.lookTarget = look
        }
        startGenerating()
        playNextWhenReady(afterGap: 0.05)
    }

    /// Injects a one-shot situational directive for the next generated turn
    /// (moderator beats like the closing round).
    func queueDirective(_ directive: String) {
        nextDirective = directive
    }

    // MARK: - Gaze choreography

    /// Non-speakers mostly watch the speaker (70%), sometimes another
    /// character (20%) or the user (10%). The speaker looks where directed.
    private func choreographGazes(speaker: CharacterEntity, turn: DirectorTurn) {
        switch turn.lookTarget {
        case "user":
            speaker.lookTarget = userHead()
        case "table":
            speaker.lookTarget = SeatingLayout.tableCenter + SIMD3<Float>(0, SeatingLayout.tableTopHeight, 0)
        case let id:
            speaker.lookTarget = characters[id]?.headWorldPosition ?? userHead()
        }
        for character in orderedCast where character.spec.id != speaker.spec.id {
            let roll = Double.random(in: 0..<1)
            if roll < 0.7 {
                character.lookTarget = speaker.headWorldPosition
            } else if roll < 0.9, let other = orderedCast.filter({ $0.spec.id != character.spec.id && $0.spec.id != speaker.spec.id }).randomElement() {
                character.lookTarget = other.headWorldPosition
            } else {
                character.lookTarget = userHead()
            }
        }
    }

    private func idleGazes() {
        for character in orderedCast {
            character.lookTarget = Bool.random()
                ? SeatingLayout.tableCenter + SIMD3<Float>(0, SeatingLayout.tableTopHeight, 0)
                : userHead()
        }
    }

    // MARK: - Per-frame

    func tick(time: Double, dt: Double) {
        lipSync.update()
        gem.update(time: time, dt: dt)
        for character in orderedCast {
            character.updateIdle(time: time, dt: dt)
        }
    }
}
