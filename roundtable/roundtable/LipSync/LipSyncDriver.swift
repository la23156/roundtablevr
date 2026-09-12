//
//  LipSyncDriver.swift
//  roundtable
//
//  Per-frame viseme weight driver: exponential attack/release smoothing plus
//  co-articulation (next viseme ramps in during the tail of the current one).
//  Call update() every frame from a scene-update subscription or task loop.
//

import Foundation
import QuartzCore

@MainActor
final class LipSyncDriver {
    private var keys: [VisemeKey] = []
    private var startTime: Double = 0
    private var avatar: LoadedAvatar?
    private var smoothed: [String: Float] = [:]
    private var lastUpdate: Double = 0

    private let attackTau = 0.045
    private let releaseTau = 0.09

    var isSpeaking: Bool { avatar != nil }

    /// Avatars without Oculus viseme morphs (e.g. the RPM "preview" rig, only
    /// mouthOpen/mouthSmile) get amplitude-driven jaw flap instead.
    private var useMouthOpenFallback = false

    func speak(track: [VisemeKey], avatar: LoadedAvatar) {
        self.keys = track
        self.avatar = avatar
        let hasVisemes = avatar.canonicalWeightNames.contains("viseme_aa")
        if !hasVisemes, !useMouthOpenFallback {
            print("LipSync: mouthOpen fallback engaged (rig has no visemes)")
        }
        self.useMouthOpenFallback = !hasVisemes
        self.startTime = CACurrentMediaTime()
        self.lastUpdate = startTime
    }

    /// Shifts the clock forward after a playback pause so visemes stay aligned.
    func shiftClock(by pausedSeconds: Double) {
        startTime += pausedSeconds
    }

    func stop() {
        guard let avatar else { return }
        var zeros: [String: Float] = [:]
        for v in VisemeMapper.allVisemes { zeros[v] = 0 }
        zeros["mouthOpen"] = 0
        avatar.setWeights(zeros)
        self.avatar = nil
        self.keys = []
        self.smoothed = [:]
    }

    func update() {
        guard let avatar, !keys.isEmpty else { return }
        let now = CACurrentMediaTime()
        let t = now - startTime
        let dt = max(now - lastUpdate, 1.0 / 240.0)
        lastUpdate = now

        // Past the end: fade everything out, then release the avatar.
        let end = keys.last.map { $0.start + $0.duration } ?? 0
        if t > end + 0.25 {
            stop()
            return
        }

        // Active key (linear scan is fine: tracks are ~100 keys, called 60x/s
        // with strong locality; start from a remembered index if it ever shows
        // up in a profile).
        var targets: [String: Float] = [:]
        for v in VisemeMapper.allVisemes { targets[v] = 0 }
        if let idx = keys.lastIndex(where: { $0.start <= t }) {
            let key = keys[idx]
            let progress = (t - key.start) / max(key.duration, 0.001)
            if progress <= 1 {
                targets[key.viseme] = key.amplitude
                // Co-articulation: blend the next viseme in over the last 30%.
                if progress > 0.7, idx + 1 < keys.count {
                    let next = keys[idx + 1]
                    let blend = Float((progress - 0.7) / 0.3)
                    targets[next.viseme] = max(targets[next.viseme] ?? 0, next.amplitude * blend * 0.6)
                    targets[key.viseme] = key.amplitude * (1 - blend * 0.5)
                }
            }
        }

        // Viseme-less rigs: collapse the active viseme's energy into mouthOpen
        // (silence maps to 0, vowels flap wider than consonants).
        if useMouthOpenFallback {
            let energy = targets.reduce(Float(0)) { $1.key == "viseme_sil" ? $0 : max($0, $1.value) }
            targets = ["mouthOpen": energy * 0.85]
        }

        // Exponential smoothing toward targets.
        var updates: [String: Float] = [:]
        for (name, target) in targets {
            let current = smoothed[name] ?? 0
            let tau = target > current ? attackTau : releaseTau
            let alpha = Float(1 - exp(-dt / tau))
            let value = current + (target - current) * alpha
            smoothed[name] = value
            updates[name] = value
        }
        avatar.setWeights(updates)
    }
}
