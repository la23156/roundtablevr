//
//  AppModel.swift
//  roundtable
//

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

    /// Freeze config and spin up a session controller before the space opens.
    /// Turn generation starts immediately so the opening line's LLM + TTS run
    /// in parallel with the immersive-space transition and scene build.
    func beginSession(config: SessionConfig, document: DiscussionDocument? = nil) {
        sessionConfig = config
        let controller = SessionController(config: config)
        controller.document = document
        sessionController = controller
        controller.prefetchOpening()
        phase = .connecting
    }

    /// Called when the immersive space is fully gone.
    func finishSession() {
        if let controller = sessionController {
            lastRecap = controller.buildRecap()
            controller.teardown()
        }
        sessionController = nil
        phase = lastRecap == nil ? .menu : .recap
    }

    func returnToMenu() {
        lastRecap = nil
        sessionConfig = nil
        phase = .menu
    }
}
