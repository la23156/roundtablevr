//
//  VisemeMapper.swift
//  roundtable
//
//  Text -> timed viseme track. Fish Audio returns no per-character timestamps,
//  so timing is estimated: each grapheme gets a duration weight, the whole
//  text is scaled to the measured audio duration, and consecutive identical
//  visemes merge. Pure functions — unit-testable.
//

import Foundation

struct VisemeKey: Equatable {
    let start: Double       // seconds from utterance start
    let duration: Double
    let viseme: String      // canonical blend-shape name, e.g. "viseme_aa"
    let amplitude: Float
}

enum VisemeMapper {

    static let allVisemes = [
        "viseme_sil", "viseme_PP", "viseme_FF", "viseme_TH", "viseme_DD",
        "viseme_kk", "viseme_CH", "viseme_SS", "viseme_nn", "viseme_RR",
        "viseme_aa", "viseme_E", "viseme_I", "viseme_O", "viseme_U",
    ]

    /// Digraphs checked before single characters.
    private static let digraphs: [String: String] = [
        "th": "viseme_TH", "ch": "viseme_CH", "sh": "viseme_CH",
        "ph": "viseme_FF", "wh": "viseme_U", "ck": "viseme_kk",
        "ng": "viseme_nn", "qu": "viseme_kk", "oo": "viseme_U",
        "ee": "viseme_I", "ou": "viseme_O", "ow": "viseme_O", "ay": "viseme_E",
    ]

    private static let singles: [Character: String] = [
        "a": "viseme_aa", "e": "viseme_E", "i": "viseme_I", "o": "viseme_O",
        "u": "viseme_U", "y": "viseme_I", "w": "viseme_U",
        "b": "viseme_PP", "p": "viseme_PP", "m": "viseme_PP",
        "f": "viseme_FF", "v": "viseme_FF",
        "d": "viseme_DD", "t": "viseme_DD",
        "k": "viseme_kk", "g": "viseme_kk", "c": "viseme_kk", "x": "viseme_kk",
        "j": "viseme_CH",
        "s": "viseme_SS", "z": "viseme_SS",
        "n": "viseme_nn", "l": "viseme_nn",
        "r": "viseme_RR", "h": "viseme_sil", "q": "viseme_kk",
    ]

    /// Relative time weight per unit (scaled to the real audio duration).
    private static func weight(of viseme: String, isSpace: Bool, isPunct: Bool) -> Double {
        if isPunct { return 3.0 }        // pauses at punctuation
        if isSpace { return 0.7 }
        switch viseme {
        case "viseme_aa", "viseme_E", "viseme_I", "viseme_O", "viseme_U": return 1.6
        default: return 1.0
        }
    }

    /// Builds the viseme track for `text` spread over `duration` seconds.
    static func track(for text: String, duration: Double) -> [VisemeKey] {
        guard duration > 0.05 else { return [] }

        // 1. Grapheme pass -> (viseme, weight) units.
        var units: [(viseme: String, weight: Double, amplitude: Float)] = []
        let lower = Array(text.lowercased())
        var i = 0
        while i < lower.count {
            let ch = lower[i]
            if i + 1 < lower.count, let v = digraphs[String([ch, lower[i + 1]])] {
                units.append((v, weight(of: v, isSpace: false, isPunct: false), 0.9))
                i += 2
                continue
            }
            if ch.isWhitespace {
                units.append(("viseme_sil", weight(of: "viseme_sil", isSpace: true, isPunct: false), 0))
            } else if ch.isPunctuation {
                units.append(("viseme_sil", weight(of: "viseme_sil", isSpace: false, isPunct: true), 0))
            } else if let v = singles[ch] {
                let isVowel = "aeiouy".contains(ch)
                units.append((v, weight(of: v, isSpace: false, isPunct: false), isVowel ? 0.95 : 0.7))
            }
            i += 1
        }
        guard !units.isEmpty else { return [] }

        // 2. Merge consecutive identical visemes.
        var merged: [(viseme: String, weight: Double, amplitude: Float)] = []
        for u in units {
            if var last = merged.last, last.viseme == u.viseme {
                last.weight += u.weight
                last.amplitude = max(last.amplitude, u.amplitude)
                merged[merged.count - 1] = last
            } else {
                merged.append(u)
            }
        }

        // 3. Scale to audio duration, clamp key lengths.
        let totalWeight = merged.reduce(0) { $0 + $1.weight }
        var keys: [VisemeKey] = []
        var t = 0.0
        for u in merged {
            let d = duration * (u.weight / totalWeight)
            keys.append(VisemeKey(start: t,
                                  duration: min(max(d, 0.04), 0.28),
                                  viseme: u.viseme,
                                  amplitude: u.amplitude))
            t += d
        }
        return keys
    }
}
