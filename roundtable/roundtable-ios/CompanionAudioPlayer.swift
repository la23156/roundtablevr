//
//  CompanionAudioPlayer.swift
//  roundtable-ios
//
//  Plays the roundtable turns on iPhone: each turnPrepared message is
//  re-synthesized locally with the same Deepgram voice (TurnSynthesizer /
//  SegmentedTurnAudio), then the host's turnStart triggers sequential
//  AVAudioPlayer playback. .mixWithOthers so we ride alongside the FaceTime
//  call's audio instead of fighting it. No audio bytes ever cross the wire.
//

import AVFoundation
import Foundation

@MainActor
final class CompanionAudioPlayer {
    /// Fired when a turn's audio actually starts / fully ends (drives the
    /// subtitle ticker + transcript in CompanionModel).
    var onTurnBegan: ((DirectorTurn) -> Void)?
    var onTurnEnded: (() -> Void)?

    private let tts = DeepgramTTSClient()
    private var prepared: [UUID: PreparedTurn] = [:]
    private var pendingStartID: UUID?
    private var currentEpoch = 0

    private var player: AVAudioPlayer?
    private var playTask: Task<Void, Never>?
    private var playingID: UUID?
    private var ducked = false

    func configureAudioSession() {
        do {
            // The FaceTime call owns the session; .playback + mixWithOthers
            // lets our synthesized voices blend in without stealing it.
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        } catch {
            print("COMPANION audio session: \(error)")
        }
    }

    /// A turn arrived from the host: synthesize it now so the audio is ready
    /// (or nearly ready) when turnStart lands.
    func enqueue(turn: DirectorTurn, id: UUID, voiceID: String, epoch: Int) {
        currentEpoch = max(currentEpoch, epoch)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let audio = try await TurnSynthesizer.synthesize(text: turn.text, voiceID: voiceID, tts: tts)
                guard epoch >= currentEpoch else { return }   // interrupted meanwhile
                prepared[id] = PreparedTurn(id: id, turn: turn, audio: audio, epoch: epoch)
                if pendingStartID == id {
                    pendingStartID = nil
                    play(id)
                }
            } catch {
                print("COMPANION synth failed: \(error)")
            }
        }
    }

    /// The host started this turn: play our local synthesis of it.
    func play(_ id: UUID) {
        guard let turn = prepared.removeValue(forKey: id) else {
            pendingStartID = id
            return
        }
        pendingStartID = nil
        stopPlayback(notify: false)
        playingID = id
        onTurnBegan?(turn.turn)

        playTask = Task { @MainActor [weak self] in
            var index = 0
            while !Task.isCancelled {
                guard let self, self.playingID == id else { return }
                // Wait for background synthesis to catch up if needed.
                while index >= turn.audio.segments.count {
                    if turn.audio.isComplete {
                        self.finishTurn(id)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(60))
                    if Task.isCancelled { return }
                }
                let segment = turn.audio.segments[index]
                do {
                    let player = try AVAudioPlayer(contentsOf: segment.url)
                    player.volume = self.ducked ? 0.12 : 1.0
                    self.player = player
                    player.play()
                    try? await Task.sleep(for: .seconds(max(segment.duration, player.duration) + 0.05))
                    if Task.isCancelled { return }
                } catch {
                    print("COMPANION play failed: \(error)")
                    self.finishTurn(id)
                    return
                }
                index += 1
                if turn.audio.isComplete, index >= turn.audio.segments.count {
                    self.finishTurn(id)
                    return
                }
            }
        }
    }

    private func finishTurn(_ id: UUID) {
        guard playingID == id else { return }
        playingID = nil
        player = nil
        onTurnEnded?()
    }

    /// The host cut the current turn (a human interjected).
    func interrupt(epoch: Int) {
        currentEpoch = max(currentEpoch, epoch)
        prepared = prepared.filter { $0.value.epoch >= currentEpoch }
        pendingStartID = nil
        stopPlayback(notify: true)
    }

    func stopAll() {
        prepared.removeAll()
        pendingStartID = nil
        stopPlayback(notify: false)
    }

    private func stopPlayback(notify: Bool) {
        playTask?.cancel()
        playTask = nil
        player?.stop()
        player = nil
        let wasPlaying = playingID != nil
        playingID = nil
        if notify, wasPlaying { onTurnEnded?() }
    }

    // Someone (here or remote) is talking: dip our TTS under their voice.
    func duck() {
        ducked = true
        player?.volume = 0.12
    }

    func unduck() {
        ducked = false
        player?.volume = 1.0
    }
}
