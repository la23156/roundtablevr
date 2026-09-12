//
//  RTMessages.swift
//  roundtable (shared: visionOS + iOS companion)
//
//  Wire protocol for the SharePlay session. Everything rides in a versioned
//  envelope over the reliable GroupSessionMessenger; only tiny speaking-level
//  pulses use the unreliable one. Messages are text + metadata only (~2 KB) —
//  audio is NEVER shipped; every device re-synthesizes TTS locally.
//

import Foundation
import simd

/// Versioned envelope so future clients can skip messages they don't know.
struct RTEnvelope: Codable, Sendable {
    static let currentVersion = 1
    var v: Int
    var msg: RTMessage

    init(_ msg: RTMessage) {
        self.v = Self.currentVersion
        self.msg = msg
    }
}

enum RTMessage: Codable, Sendable {
    // Host -> all: the director LLM produced a turn (sent before TTS).
    case turnPrepared(TurnPreparedPayload)
    // Host -> all: playback of a prepared turn just started on the host.
    case turnStart(turnID: UUID, hostTime: Double)
    // Host -> all: the current turn was cut off by a human.
    case turnInterrupted(turnID: UUID, spokenFraction: Double, epoch: Int)
    // Any device -> all: its local human started speaking (everyone ducks).
    case userSpeechStarted(name: String)
    // Any device -> all: final transcript of that human's interjection.
    case userSpeechFinal(name: String, text: String, facedCharacterID: String?)
    // Any device -> all: who am I (display name, chosen portrait, platform).
    case identity(IdentityPayload)
    // Host -> all: iPhone guests' easel slot assignments (join order).
    case guestSeats([GuestSeatAssignment])
    // Host -> newcomer: everything needed to join mid-session.
    case snapshot(SessionSnapshot)
    // Host -> all: the presentation board flipped to a new page.
    case pageChanged(index: Int)
    // Host -> all: the session is over (host is leaving).
    case sessionEnded
}

struct TurnPreparedPayload: Codable, Sendable {
    var turnID: UUID
    var epoch: Int
    var voiceID: String
    /// The DirectorTurn, JSON-encoded so the envelope stays schema-stable.
    var turnJSON: Data

    init(turnID: UUID, epoch: Int, voiceID: String, turn: DirectorTurn) throws {
        self.turnID = turnID
        self.epoch = epoch
        self.voiceID = voiceID
        self.turnJSON = try JSONEncoder().encode(turn)
    }

    func turn() throws -> DirectorTurn {
        try JSONDecoder().decode(DirectorTurn.self, from: turnJSON)
    }
}

struct IdentityPayload: Codable, Sendable, Equatable {
    var name: String
    /// Cast id whose portrait the guest picked as their table card (iOS).
    var characterID: String?
    /// True for Vision Pro participants (Spatial Persona seats them); false
    /// for iPhone companions (they get a rendered card easel instead).
    var hasPersona: Bool
}

struct GuestSeatAssignment: Codable, Sendable, Equatable {
    var participantID: UUID
    var slot: Int          // index into SeatingLayout.humanPersonaSeats()
}

/// Late-joiner catch-up. Cast rides as ids (built-ins resolve locally; web
/// customs resolve from the CharacterStore cache).
struct SessionSnapshot: Codable, Sendable {
    struct TopicInfo: Codable, Sendable {
        var id: String
        var emoji: String
        var title: String
        var subtitle: String
        var promptSeed: String
    }
    struct SettingsInfo: Codable, Sendable {
        var sessionMinutes: Int
        var paceMultiplier: Double
        var subtitlesEnabled: Bool
    }
    struct TranscriptItem: Codable, Sendable {
        var speakerName: String
        var text: String
        var wasInterrupted: Bool
    }
    struct InsightItem: Codable, Sendable {
        var title: String
        var speakerName: String
        var sparkedByUser: Bool
    }

    var topic: TopicInfo
    var castIDs: [String]
    var settings: SettingsInfo
    var transcriptTail: [TranscriptItem]   // last ~20 lines
    var insights: [InsightItem]
    var guestSeats: [GuestSeatAssignment]
    /// Document mode: title + page count + the page currently on the board.
    /// The PDF itself arrives separately via GroupSessionJournal.
    var documentTitle: String?
    var documentPageCount: Int
    var currentPageIndex: Int
}

/// Unreliable channel: mic level pulses that drive guest-card rim glow.
struct SpeakingLevelMessage: Codable, Sendable {
    var level: Float       // 0...1
}

// MARK: - -rtMessageTest self-check

/// Encodes and decodes one exemplar of every RTMessage case, printing
/// PASS/FAIL per case. Run under the -rtMessageTest launch argument.
enum RTMessageSelfTest {
    static func run() {
        let turn = DirectorTurn(
            speaker: "elowen",
            text: "Welcome to the table — tonight we ask whether the stars are listening.",
            emotion: .warm, lookTarget: "user", gesture: .handOpen,
            insight: "Stars as silent audience", invitesUser: true)
        let payload = try? TurnPreparedPayload(
            turnID: UUID(), epoch: 3, voiceID: "aura-2-hera-en", turn: turn)
        guard let payload else {
            print("RT-TEST turnPrepared payload: FAIL (encode)")
            return
        }
        let snapshot = SessionSnapshot(
            topic: .init(id: "aliens", emoji: "👽", title: "Do aliens exist?",
                         subtitle: "Fermi", promptSeed: "seed"),
            castIDs: ["elowen", "marcus", "zara", "nadia"],
            settings: .init(sessionMinutes: 15, paceMultiplier: 1.0, subtitlesEnabled: true),
            transcriptTail: [.init(speakerName: "Marcus Vale", text: "The numbers say otherwise.", wasInterrupted: false)],
            insights: [.init(title: "Silence is data", speakerName: "Marcus Vale", sparkedByUser: true)],
            guestSeats: [.init(participantID: UUID(), slot: 0)],
            documentTitle: "SamplePitch", documentPageCount: 9, currentPageIndex: 2)

        let cases: [(String, RTMessage)] = [
            ("turnPrepared", .turnPrepared(payload)),
            ("turnStart", .turnStart(turnID: UUID(), hostTime: 1234.5)),
            ("turnInterrupted", .turnInterrupted(turnID: UUID(), spokenFraction: 0.42, epoch: 4)),
            ("userSpeechStarted", .userSpeechStarted(name: "Latif")),
            ("userSpeechFinal", .userSpeechFinal(name: "Latif", text: "But what about the Drake equation?", facedCharacterID: "marcus")),
            ("identity", .identity(.init(name: "Latif", characterID: "zara", hasPersona: false))),
            ("guestSeats", .guestSeats([.init(participantID: UUID(), slot: 1)])),
            ("snapshot", .snapshot(snapshot)),
            ("pageChanged", .pageChanged(index: 3)),
            ("sessionEnded", .sessionEnded),
        ]

        var allPassed = true
        for (name, message) in cases {
            do {
                let data = try JSONEncoder().encode(RTEnvelope(message))
                let decoded = try JSONDecoder().decode(RTEnvelope.self, from: data)
                let roundTrip = try JSONEncoder().encode(decoded)
                let ok = decoded.v == RTEnvelope.currentVersion && !roundTrip.isEmpty
                // Case-specific integrity spot checks.
                var detail = "\(data.count)B"
                switch decoded.msg {
                case .turnPrepared(let p):
                    let t = try p.turn()
                    if t != turn { throw NSError(domain: "rt", code: 1) }
                    detail += " turn=\(t.speaker)"
                case .snapshot(let s):
                    if s.castIDs.count != 4 || s.currentPageIndex != 2 { throw NSError(domain: "rt", code: 2) }
                case .userSpeechFinal(let n, _, let faced):
                    if n != "Latif" || faced != "marcus" { throw NSError(domain: "rt", code: 3) }
                default: break
                }
                print("RT-TEST \(name): \(ok ? "PASS" : "FAIL") (\(detail))")
                if !ok { allPassed = false }
            } catch {
                print("RT-TEST \(name): FAIL (\(error))")
                allPassed = false
            }
        }
        // Speaking-level pulse (unreliable channel).
        do {
            let data = try JSONEncoder().encode(SpeakingLevelMessage(level: 0.7))
            let back = try JSONDecoder().decode(SpeakingLevelMessage.self, from: data)
            print("RT-TEST speakingLevel: \(abs(back.level - 0.7) < 0.001 ? "PASS" : "FAIL") (\(data.count)B)")
        } catch {
            print("RT-TEST speakingLevel: FAIL (\(error))")
            allPassed = false
        }
        print("RT-TEST overall: \(allPassed ? "PASS" : "FAIL")")

        printTemplateMath()
    }

    /// The simulator can't spawn Spatial Participants from the CLI, so verify
    /// the seating template's math directly: seat positions must sit on the
    /// chair ellipse and all human seats must be >= 1 m apart.
    private static func printTemplateMath() {
        let a = SeatingLayout.tableSemiX + SeatingLayout.seatSetback
        let b = SeatingLayout.tableSemiZ + SeatingLayout.seatSetback
        let center = SeatingLayout.tableCenter

        var all: [(String, SIMD3<Float>)] = [("host", SeatingLayout.hostSeatPosition)]
        for (i, seat) in SeatingLayout.humanPersonaSeats().enumerated() {
            all.append(("guest\(i)", seat.position))
        }
        for (name, p) in all {
            let dx = (p.x - center.x) / a
            let dz = (p.z - center.z) / b
            let ellipseError = abs(dx * dx + dz * dz - 1)
            print(String(format: "RT-TEMPLATE %@ position=(%.3f, %.3f) onEllipse=%@ (err=%.4f)",
                         name, p.x, p.z,
                         name == "host" ? "n/a(origin)" : (ellipseError < 0.01 ? "YES" : "NO"),
                         ellipseError))
        }
        var minDistance = Float.greatestFiniteMagnitude
        for i in 0..<all.count {
            for j in (i + 1)..<all.count {
                let d = simd_distance(all[i].1, all[j].1)
                minDistance = min(minDistance, d)
                print(String(format: "RT-TEMPLATE dist %@<->%@ = %.2fm %@",
                             all[i].0, all[j].0, d, d >= 1.0 ? "OK" : "TOO CLOSE"))
            }
        }
        print(String(format: "RT-TEMPLATE spacing: %@ (min %.2fm)",
                     minDistance >= 1.0 ? "PASS" : "FAIL", minDistance))
    }
}
