//
//  CharacterAudio.swift
//  roundtable
//
//  Spatial speech playback: each character gets a "MouthAudio" child entity at
//  head height with a beam-directivity SpatialAudioComponent.
//

import AVFoundation
import Foundation
import RealityKit

@MainActor
enum CharacterAudio {

    /// Finds or creates the character's mouth audio emitter.
    static func mouthEntity(on root: Entity, headHeight: Float = SeatingLayout.seatedEyeHeight) -> Entity {
        if let existing = root.findEntity(named: "MouthAudio") { return existing }
        let mouth = Entity()
        mouth.name = "MouthAudio"
        mouth.position = [0, headHeight, 0]
        mouth.components.set(SpatialAudioComponent(directivity: .beam(focus: 0.4)))
        root.addChild(mouth)
        return mouth
    }

    /// Plays a downloaded clip on the entity. Returns the playback controller;
    /// completion fires via `controller.completionHandler`.
    static func play(url: URL, on entity: Entity) async throws -> AudioPlaybackController {
        let resource = try await AudioFileResource(
            contentsOf: url,
            configuration: .init(loadingStrategy: .preload, shouldLoop: false)
        )
        return entity.playAudio(resource)
    }
}
