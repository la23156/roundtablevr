//
//  CompanionApp.swift
//  roundtable-ios
//
//  iPhone companion for the Roundtable: joins the SharePlay session from a
//  FaceTime call, appears at the table as a card easel, hears the discussion
//  (locally re-synthesized TTS), reads along, and can interject by voice.
//

import AVFoundation
import SwiftUI
import PDFKit

@main
struct CompanionApp: App {
    @State private var model = CompanionModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if model.seated {
                    CompanionSessionView()
                } else {
                    JoinView()
                }
            }
            .environment(model)
        }
    }
}

/// All companion state: SharePlay plumbing, transcript mirror, audio player,
/// interjection mic.
@MainActor
@Observable
final class CompanionModel {
    let coordinator = GroupSessionCoordinator()
    let audio = CompanionAudioPlayer()
    @ObservationIgnored private let speech = SpeechInput()

    // Identity picked on the join screen.
    var guestName: String = ""
    var chosenCharacterID: String?
    /// True once the user confirmed identity inside an active session.
    private(set) var seated = false

    // Session mirror.
    private(set) var topicTitle: String = "Roundtable"
    struct Line: Identifiable {
        let id = UUID()
        let speaker: String
        let text: String
    }
    private(set) var transcript: [Line] = []
    private(set) var subtitle: (speaker: String, text: String)?
    private(set) var insightCount = 0
    private(set) var micLive = false

    // Document mode.
    @ObservationIgnored private var pdf: PDFDocument?
    private(set) var currentPageIndex = 0
    private(set) var pageImage: UIImage?

    /// Cast names for subtitles (built-in roster mirror; unknown ids pass through).
    private let castNames: [String: String] = [
        "elowen": "Prof. Elowen Hart", "marcus": "Marcus Vale", "zara": "Zara Moon",
        "dev": "Dr. Dev Okafor", "nadia": "Nadia Reyes",
    ]

    init() {
        wireCoordinator()
        wireAudio()
        wireSpeech()
        coordinator.startSessionListener()
        if ProcessInfo.processInfo.arguments.contains("-rtMessageTest") {
            RTMessageSelfTest.run()
        }
    }

    // MARK: - Join flow

    var sessionActive: Bool { coordinator.sessionActive }
    var participantCount: Int { coordinator.participantCount }

    func activate() async {
        await coordinator.activate(topicTitle: "Roundtable")
    }

    func takeSeat() {
        let trimmed = guestName.trimmingCharacters(in: .whitespacesAndNewlines)
        coordinator.localName = trimmed.isEmpty ? "iPhone Guest" : trimmed
        coordinator.localCharacterID = chosenCharacterID
        coordinator.broadcastIdentity()
        seated = true
        audio.configureAudioSession()
    }

    // MARK: - Wiring

    private func wireCoordinator() {
        coordinator.onMessage = { [weak self] message, participantID in
            self?.handle(message, from: participantID)
        }
        coordinator.onPDFData = { [weak self] data in
            guard let self else { return }
            pdf = PDFDocument(data: data)
            renderCurrentPage()
        }
        coordinator.onSessionEnded = { [weak self] in
            guard let self else { return }
            audio.stopAll()
            stopMic()
            seated = false
            transcript.removeAll()
            subtitle = nil
            pdf = nil
            pageImage = nil
        }
    }

    private func wireAudio() {
        audio.onTurnBegan = { [weak self] turn in
            guard let self else { return }
            let name = castNames[turn.speaker] ?? turn.speaker.capitalized
            subtitle = (name, turn.text)
            transcript.append(Line(speaker: name, text: turn.text))
            if turn.insight != nil { insightCount += 1 }
        }
        audio.onTurnEnded = { [weak self] in
            self?.subtitle = nil
        }
    }

    private func wireSpeech() {
        speech.groupCallActive = true   // we're always inside a FaceTime call
        speech.onSpeechStart = { [weak self] in
            guard let self else { return }
            coordinator.send(.userSpeechStarted(name: coordinator.localName))
            audio.duck()
        }
        speech.onLevel = { [weak self] level in
            self?.coordinator.sendSpeakingLevel(level)
        }
        speech.onFinal = { [weak self] text in
            guard let self else { return }
            let words = text.split(separator: " ").count
            guard words >= 2, !isLikelyEcho(text) else {
                coordinator.send(.userSpeechFinal(name: coordinator.localName,
                                                  text: "", facedCharacterID: nil))
                audio.unduck()
                return
            }
            print("COMPANION user said: \(text)")
            coordinator.send(.userSpeechFinal(name: coordinator.localName,
                                              text: text, facedCharacterID: nil))
            transcript.append(Line(speaker: "You", text: text))
            audio.unduck()
        }
    }

    /// Same echo defense as visionOS: the iPhone speaker plays the cast's
    /// voices right next to the mic.
    private func isLikelyEcho(_ text: String) -> Bool {
        func tokens(_ s: String) -> Set<String> {
            Set(s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
        }
        let heard = tokens(text)
        guard !heard.isEmpty else { return true }
        for line in transcript.suffix(3) where line.speaker != "You" {
            let spoken = tokens(line.text)
            guard !spoken.isEmpty else { continue }
            if Double(heard.intersection(spoken).count) / Double(heard.count) > 0.45 { return true }
        }
        return false
    }

    // MARK: - Incoming messages

    private func handle(_ message: RTMessage, from participantID: UUID) {
        switch message {
        case .snapshot(let snapshot):
            topicTitle = snapshot.topic.title
            transcript = snapshot.transcriptTail.map {
                Line(speaker: $0.speakerName, text: $0.text)
            }
            insightCount = snapshot.insights.count
            currentPageIndex = snapshot.currentPageIndex
            renderCurrentPage()

        case .turnPrepared(let payload):
            guard let turn = try? payload.turn() else { return }
            audio.enqueue(turn: turn, id: payload.turnID,
                          voiceID: payload.voiceID, epoch: payload.epoch)

        case .turnStart(let turnID, _):
            audio.play(turnID)

        case .turnInterrupted(_, _, let epoch):
            audio.interrupt(epoch: epoch)
            subtitle = nil

        case .userSpeechStarted:
            audio.duck()

        case .userSpeechFinal(let name, let text, _):
            audio.unduck()
            guard !text.isEmpty else { return }
            transcript.append(Line(speaker: name, text: text))
            subtitle = (name, text)

        case .pageChanged(let index):
            currentPageIndex = index
            renderCurrentPage()

        case .identity, .guestSeats:
            break

        case .sessionEnded:
            break   // onSessionEnded callback does the cleanup
        }
    }

    private func renderCurrentPage() {
        guard let pdf, pdf.pageCount > 0 else {
            pageImage = nil
            return
        }
        let index = min(max(currentPageIndex, 0), pdf.pageCount - 1)
        guard let page = pdf.page(at: index) else { return }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 1, bounds.height > 1 else { return }
        let width: CGFloat = 900
        let size = CGSize(width: width, height: width * bounds.height / bounds.width)
        pageImage = page.thumbnail(of: size, for: .mediaBox)
    }

    var pageCount: Int { pdf?.pageCount ?? 0 }
    var hasDocument: Bool { pdf != nil }

    // MARK: - Interjection mic

    func toggleMic() {
        micLive ? stopMic() : startMic()
    }

    private func startMic() {
        guard !micLive else { return }
        micLive = true
        Task { await speech.start() }
    }

    private func stopMic() {
        guard micLive else { return }
        micLive = false
        speech.stop()
    }
}
