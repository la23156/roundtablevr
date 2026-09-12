//
//  GroupSessionCoordinator.swift
//  roundtable (shared: visionOS + iOS companion)
//
//  Owns the SharePlay plumbing: session listener, join, host election,
//  reliable/unreliable messengers, journal (PDF transfer), participant
//  bookkeeping, and (visionOS) the system coordinator configuration + group
//  immersion style loop. App logic hangs off the callbacks; with no active
//  session every send is a silent no-op so the solo path is untouched.
//

import Combine
import CoreTransferable
import Foundation
import GroupActivities
import Observation
import SwiftUI   // _GroupActivities_SwiftUI overlay: groupImmersionStyle
import UniformTypeIdentifiers

/// PDF payload for GroupSessionJournal (document sessions send the deck once).
struct RoundtablePDF: Transferable, Sendable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .pdf,
                           exporting: { $0.data },
                           importing: { RoundtablePDF(data: $0) })
    }
}

@MainActor
@Observable
final class GroupSessionCoordinator {

    // MARK: - Observable state

    private(set) var sessionActive = false
    /// True when this device initiated the session (it runs the director).
    private(set) var isHost = false
    private(set) var participantCount = 1
    /// Remote humans by participant UUID (filled from identity messages).
    private(set) var humans: [UUID: IdentityPayload] = [:]
    /// iPhone guests' easel slots (host-assigned, mirrored everywhere).
    private(set) var guestSeatSlots: [UUID: Int] = [:]

    /// Local identity broadcast to the table.
    var localName: String = GroupSessionCoordinator.defaultLocalName()
    var localCharacterID: String?

    // MARK: - Callbacks (all fired on the main actor)

    @ObservationIgnored var onMessage: ((RTMessage, UUID) -> Void)?
    @ObservationIgnored var onSpeakingLevel: ((UUID, Float) -> Void)?
    @ObservationIgnored var onSessionJoined: ((_ isHost: Bool) -> Void)?
    @ObservationIgnored var onSessionEnded: (() -> Void)?
    /// New remote participants became active (host sends them the snapshot).
    @ObservationIgnored var onNewParticipants: ((Set<Participant>) -> Void)?
    @ObservationIgnored var onPDFData: ((Data) -> Void)?
    #if os(visionOS)
    /// Group immersion style changed: true = open the shared space, false = close.
    @ObservationIgnored var onGroupImmersionChange: ((Bool) -> Void)?
    #endif

    // MARK: - Internals

    @ObservationIgnored private(set) var session: GroupSession<RoundtableActivity>?
    @ObservationIgnored private var reliable: GroupSessionMessenger?
    @ObservationIgnored private var unreliable: GroupSessionMessenger?
    @ObservationIgnored private var journal: GroupSessionJournal?
    @ObservationIgnored private var sessionTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var listenerTask: Task<Void, Never>?
    @ObservationIgnored private var pdfSent = false
    #if os(visionOS)
    @ObservationIgnored private(set) var systemCoordinator: SystemCoordinator?
    #endif

    var localParticipantID: UUID? { session?.localParticipant.id }

    private static func defaultLocalName() -> String {
        #if os(visionOS)
        return "Vision Pro Guest"
        #else
        return "iPhone Guest"
        #endif
    }

    // MARK: - Lifecycle

    /// Start listening for incoming sessions (call once at app launch).
    func startSessionListener() {
        guard listenerTask == nil else { return }
        listenerTask = Task { [weak self] in
            for await session in RoundtableActivity.sessions() {
                self?.configure(session)
            }
        }
    }

    /// Activate the activity (from the menu / join screen — NEVER while a
    /// group immersive space is open: activation would dismiss it).
    @discardableResult
    func activate(topicTitle: String) async -> Bool {
        let activity = RoundtableActivity(topicTitle: topicTitle)
        switch await activity.prepareForActivation() {
        case .activationPreferred:
            let ok = (try? await activity.activate()) ?? false
            print("GROUP activate: \(ok ? "activated" : "failed")")
            return ok
        case .activationDisabled:
            print("GROUP activate: activation disabled (no FaceTime call / not eligible)")
            return false
        case .cancelled:
            print("GROUP activate: user cancelled")
            return false
        @unknown default:
            return false
        }
    }

    /// Leave the session locally (host leaving ends it for everyone via the
    /// endsWhenInitiatorLeaves lifetime policy).
    func leave() {
        if isHost {
            send(.sessionEnded)
            session?.end()
        } else {
            session?.leave()
        }
        tearDownSession()
    }

    private func configure(_ session: GroupSession<RoundtableActivity>) {
        tearDownSession()
        self.session = session
        isHost = session.isLocallyInitiated
        print("GROUP session received (host=\(isHost)) topic=\(session.activity.topicTitle)")

        let reliable = GroupSessionMessenger(session: session, deliveryMode: .reliable)
        let unreliable = GroupSessionMessenger(session: session, deliveryMode: .unreliable)
        let journal = GroupSessionJournal(session: session)
        self.reliable = reliable
        self.unreliable = unreliable
        self.journal = journal

        // Reliable protocol messages.
        sessionTasks.append(Task { [weak self] in
            for await (envelope, context) in reliable.messages(of: RTEnvelope.self) {
                guard envelope.v == RTEnvelope.currentVersion else { continue }
                self?.handle(envelope.msg, from: context.source.id)
            }
        })
        // Unreliable speaking-level pulses.
        sessionTasks.append(Task { [weak self] in
            for await (message, context) in unreliable.messages(of: SpeakingLevelMessage.self) {
                self?.onSpeakingLevel?(context.source.id, message.level)
            }
        })
        // Journal: the PDF for document sessions.
        sessionTasks.append(Task { [weak self] in
            for await attachments in journal.attachments {
                for attachment in attachments {
                    if let pdf = try? await attachment.load(RoundtablePDF.self) {
                        print("GROUP journal PDF received (\(pdf.data.count) bytes)")
                        self?.onPDFData?(pdf.data)
                    }
                }
            }
        })
        // Session state.
        sessionTasks.append(Task { [weak self] in
            for await state in session.$state.values {
                if case .invalidated(let reason) = state {
                    print("GROUP session invalidated: \(reason)")
                    self?.tearDownSession()
                    break
                }
            }
        })
        // Participant bookkeeping + newcomer catch-up.
        sessionTasks.append(Task { [weak self] in
            var known: Set<Participant> = []
            for await active in session.$activeParticipants.values {
                guard let self else { break }
                self.participantCount = active.count
                let newcomers = active.subtracting(known).filter { $0 != session.localParticipant }
                let departed = known.subtracting(active)
                known = active
                for gone in departed {
                    self.humans[gone.id] = nil
                    self.guestSeatSlots[gone.id] = nil
                }
                if !newcomers.isEmpty {
                    // Give the newcomer's messenger a beat to come up.
                    try? await Task.sleep(for: .milliseconds(600))
                    self.send(.identity(IdentityPayload(
                        name: self.localName,
                        characterID: self.localCharacterID,
                        hasPersona: self.localHasPersona)),
                        to: .only(Set(newcomers)))
                    self.onNewParticipants?(Set(newcomers))
                }
            }
        })

        #if os(visionOS)
        sessionTasks.append(Task { [weak self] in
            guard let coordinator = await session.systemCoordinator else { return }
            var config = SystemCoordinator.Configuration()
            config.supportsGroupImmersiveSpace = true
            config.spatialTemplatePreference = .custom(RoundtableTemplate())
            coordinator.configuration = config
            self?.systemCoordinator = coordinator
            for await style in coordinator.groupImmersionStyle {
                print("GROUP immersion style -> \(style == nil ? "none" : "immersive")")
                self?.onGroupImmersionChange?(style != nil)
            }
        })
        #endif

        session.join()
        sessionActive = true
        onSessionJoined?(isHost)
        // Introduce ourselves to everyone already in the session.
        send(.identity(IdentityPayload(name: localName,
                                       characterID: localCharacterID,
                                       hasPersona: localHasPersona)))
    }

    private var localHasPersona: Bool {
        #if os(visionOS)
        return true
        #else
        return false
        #endif
    }

    private func handle(_ message: RTMessage, from participantID: UUID) {
        // Coordinator-level bookkeeping first, then hand off to the app.
        switch message {
        case .identity(let identity):
            humans[participantID] = identity
        case .guestSeats(let assignments):
            for assignment in assignments {
                guestSeatSlots[assignment.participantID] = assignment.slot
            }
        case .snapshot(let snapshot):
            for assignment in snapshot.guestSeats {
                guestSeatSlots[assignment.participantID] = assignment.slot
            }
        case .sessionEnded:
            onMessage?(message, participantID)
            tearDownSession()
            return
        default:
            break
        }
        onMessage?(message, participantID)
    }

    private func tearDownSession() {
        let wasActive = sessionActive
        sessionTasks.forEach { $0.cancel() }
        sessionTasks.removeAll()
        reliable = nil
        unreliable = nil
        journal = nil
        session = nil
        #if os(visionOS)
        systemCoordinator = nil
        #endif
        humans.removeAll()
        guestSeatSlots.removeAll()
        participantCount = 1
        pdfSent = false
        sessionActive = false
        isHost = false
        if wasActive { onSessionEnded?() }
    }

    // MARK: - Sending

    func send(_ message: RTMessage, to participants: Participants = .all) {
        guard sessionActive, let reliable else { return }
        Task {
            do {
                try await reliable.send(RTEnvelope(message), to: participants)
            } catch {
                print("GROUP send failed (\(message)): \(error)")
            }
        }
    }

    func sendSpeakingLevel(_ level: Float) {
        guard sessionActive, let unreliable else { return }
        Task {
            try? await unreliable.send(SpeakingLevelMessage(level: level))
        }
    }

    /// Host, once per document session: ship the PDF via the journal.
    func sharePDF(_ data: Data) {
        guard sessionActive, isHost, !pdfSent, let journal else { return }
        pdfSent = true
        Task {
            do {
                _ = try await journal.add(RoundtablePDF(data: data))
                print("GROUP journal PDF shared (\(data.count) bytes)")
            } catch {
                print("GROUP journal PDF share failed: \(error)")
            }
        }
    }

    /// Host: assign the next free easel slot to an iPhone guest and broadcast.
    func assignGuestSeat(for participantID: UUID) {
        guard isHost, guestSeatSlots[participantID] == nil else { return }
        let used = Set(guestSeatSlots.values)
        guard let free = (0..<SeatingLayout.maxHumanGuests).first(where: { !used.contains($0) }) else { return }
        guestSeatSlots[participantID] = free
        send(.guestSeats(guestSeatSlots.map { GuestSeatAssignment(participantID: $0.key, slot: $0.value) }))
    }

    func displayName(for participantID: UUID) -> String {
        humans[participantID]?.name ?? "Guest"
    }

    /// Re-announce the local identity (e.g. the iPhone guest picked a name
    /// and card after joining).
    func broadcastIdentity() {
        send(.identity(IdentityPayload(name: localName,
                                       characterID: localCharacterID,
                                       hasPersona: localHasPersona)))
    }
}
