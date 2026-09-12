//
//  AppModel.swift
//  roundtable
//

import GroupActivities
import SwiftUI

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    static let mainWindowID = "main"
    static let castTableWindowID = "castTable"
    static let immersiveSpaceID = "RoundtableSpace"
    let immersiveSpaceID = AppModel.immersiveSpaceID

    /// Cast selection — single source of truth shared by the 2D picker and
    /// the 3D card table (moderator always included).
    var selectedCastIDs: Set<String> = ["elowen", "marcus", "zara", "nadia"]

    /// Built-in + web-created characters (fetched from the platform API).
    let characterStore = CharacterStore()

    // MARK: - SharePlay

    /// All GroupActivities plumbing. With no active session, everything below
    /// behaves exactly as the solo app.
    let groupCoordinator = GroupSessionCoordinator()

    /// Set by the systemCoordinator.groupImmersionStyle loop: the shared
    /// immersive space should be open (replicas follow the host in/out).
    var groupWantsImmersive = false
    /// Replica: the host's catch-up snapshot (needed before we can build a
    /// session config). Consumed by beginReplicaSession.
    var pendingSnapshot: SessionSnapshot?
    /// Replica: PDF that arrived from the journal before the controller existed.
    var pendingPDFData: Data?
    /// Bumped whenever a replica-start precondition changes (MenuView reacts).
    var replicaStartTick = 0
    /// Set when the group session ends while immersed (ImmersiveView reacts).
    var groupSessionEndedWhileImmersed = false

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed

    enum Phase {
        case menu
        case connecting   // session config frozen, immersive space opening
        case inSession
        case recap
    }
    var phase = Phase.menu

    var sessionConfig: SessionConfig?
    var sessionController: SessionController?
    var lastRecap: SessionRecap?

    init() {
        wireGroupCoordinator()
        groupCoordinator.startSessionListener()
    }

    private func wireGroupCoordinator() {
        groupCoordinator.onMessage = { [weak self] message, participantID in
            guard let self else { return }
            if case .snapshot(let snapshot) = message, sessionController == nil {
                // Replica joining: hold the snapshot until the immersion
                // style says go (see MenuView.startReplicaIfReady).
                pendingSnapshot = snapshot
                replicaStartTick += 1
                print("GROUP snapshot received (\(snapshot.castIDs.count) cast, \(snapshot.transcriptTail.count) lines)")
            }
            sessionController?.handleGroupMessage(message, from: participantID)
        }
        groupCoordinator.onSpeakingLevel = { [weak self] participantID, level in
            self?.sessionController?.handleSpeakingLevel(level, from: participantID)
        }
        groupCoordinator.onNewParticipants = { [weak self] newcomers in
            guard let self, groupCoordinator.isHost else { return }
            // Late joiners get the snapshot (and the PDF rides the journal,
            // which replays attachments to newcomers automatically).
            if let controller = sessionController {
                groupCoordinator.send(.snapshot(controller.buildSnapshot()), to: .only(newcomers))
            }
        }
        groupCoordinator.onPDFData = { [weak self] data in
            guard let self, !groupCoordinator.isHost else { return }
            if let controller = sessionController, controller.isReplicaSession,
               let snapshot = pendingSnapshot, let title = snapshot.documentTitle {
                controller.applyRemoteDocument(data: data, title: title,
                                               pageIndex: snapshot.currentPageIndex)
            } else {
                pendingPDFData = data
            }
        }
        groupCoordinator.onSessionEnded = { [weak self] in
            guard let self else { return }
            pendingSnapshot = nil
            pendingPDFData = nil
            groupWantsImmersive = false
            if phase == .inSession, sessionController?.isGroupSession == true {
                groupSessionEndedWhileImmersed = true
            }
        }
        groupCoordinator.onGroupImmersionChange = { [weak self] wantsImmersive in
            guard let self else { return }
            groupWantsImmersive = wantsImmersive
            replicaStartTick += 1
            if !wantsImmersive, phase == .inSession, sessionController?.isGroupSession == true {
                groupSessionEndedWhileImmersed = true
            }
        }
    }

    /// Freeze config and spin up a session controller before the space opens.
    /// Turn generation starts immediately so the opening line's LLM + TTS run
    /// in parallel with the immersive-space transition and scene build.
    func beginSession(config: SessionConfig, document: DiscussionDocument? = nil) {
        sessionConfig = config
        let controller = SessionController(config: config, coordinator: groupCoordinator)
        controller.document = document
        sessionController = controller
        controller.prefetchOpening()
        phase = .connecting
        // Host with guests already waiting in the lobby: send them the
        // session snapshot now so they can follow us into the space.
        if groupCoordinator.sessionActive, groupCoordinator.isHost {
            groupCoordinator.send(.snapshot(controller.buildSnapshot()))
        }
    }

    /// SharePlay replica: build a session from the host's snapshot. Returns
    /// false when the cast can't be resolved locally.
    @discardableResult
    func beginReplicaSession(snapshot: SessionSnapshot) -> Bool {
        let cast = snapshot.castIDs.compactMap { characterStore.spec(for: $0) }
        guard !cast.isEmpty else {
            print("GROUP replica: no resolvable cast in snapshot \(snapshot.castIDs)")
            return false
        }
        if cast.count != snapshot.castIDs.count {
            print("GROUP replica: dropped \(snapshot.castIDs.count - cast.count) unknown cast member(s)")
        }
        let topic = TopicCard(id: snapshot.topic.id,
                              emoji: snapshot.topic.emoji,
                              title: snapshot.topic.title,
                              subtitle: snapshot.topic.subtitle,
                              promptSeed: snapshot.topic.promptSeed,
                              wantsFreshFacts: false)
        var settings = SessionSettings()
        settings.sessionMinutes = snapshot.settings.sessionMinutes
        settings.paceMultiplier = snapshot.settings.paceMultiplier
        settings.subtitlesEnabled = snapshot.settings.subtitlesEnabled
        settings.freshFactsEnabled = false

        var documentInfo: DiscussionDocumentInfo?
        if let title = snapshot.documentTitle {
            documentInfo = DiscussionDocumentInfo(
                title: title, summary: "", entities: [],
                pageTexts: Array(repeating: "", count: snapshot.documentPageCount))
        }
        let config = SessionConfig(topic: topic, cast: cast, settings: settings,
                                   document: documentInfo)
        sessionConfig = config
        let controller = SessionController(config: config, coordinator: groupCoordinator,
                                           replica: true)
        controller.applySnapshot(snapshot)
        sessionController = controller
        phase = .connecting
        // PDF may have raced ahead of the controller.
        if let data = pendingPDFData, let title = snapshot.documentTitle {
            controller.applyRemoteDocument(data: data, title: title,
                                           pageIndex: snapshot.currentPageIndex)
            pendingPDFData = nil
        }
        print("GROUP replica session staged: \(topic.title) with \(cast.count) cast")
        return true
    }

    /// Called when the immersive space is fully gone.
    func finishSession() {
        if let controller = sessionController {
            lastRecap = controller.buildRecap()
            controller.teardown()
            // Leaving the table also leaves the SharePlay session (a host
            // leaving ends it for everyone: endsWhenInitiatorLeaves).
            if controller.isGroupSession, groupCoordinator.sessionActive {
                groupCoordinator.leave()
            }
        }
        groupSessionEndedWhileImmersed = false
        pendingSnapshot = nil
        pendingPDFData = nil
        sessionController = nil
        phase = lastRecap == nil ? .menu : .recap
    }

    func returnToMenu() {
        lastRecap = nil
        sessionConfig = nil
        phase = .menu
    }
}
