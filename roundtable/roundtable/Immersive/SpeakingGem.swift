//
//  SpeakingGem.swift
//  roundtable
//
//  The green gem that hovers and slowly bobs above whoever is speaking.
//

import RealityKit
import UIKit

@MainActor
final class SpeakingGem {
    let entity: Entity
    private var baseY: Float = 0.48
    private var visible = false

    init() {
        // Low-poly gem: a box rotated onto its corner reads as a crystal.
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.15, green: 0.95, blue: 0.45, alpha: 1))
        material.emissiveColor = .init(color: UIColor(red: 0.1, green: 1.0, blue: 0.4, alpha: 1))
        material.emissiveIntensity = 2.2
        material.roughness = .init(floatLiteral: 0.15)
        material.metallic = .init(floatLiteral: 0.1)

        let model = ModelEntity(mesh: .generateBox(size: 0.075, cornerRadius: 0.008), materials: [material])
        model.orientation = simd_quatf(angle: .pi / 4, axis: normalize(SIMD3<Float>(1, 0, 1)))

        entity = Entity()
        entity.name = "SpeakingGem"
        entity.addChild(model)
        entity.components.set(OpacityComponent(opacity: 0))
    }

    /// Moves the gem above `character`'s head (or hides it if nil).
    func attach(to character: CharacterEntity?) {
        guard let character else {
            visible = false
            entity.components.set(OpacityComponent(opacity: 0))
            return
        }
        entity.removeFromParent()
        character.anchor.addChild(entity)
        // Slightly toward the table (-Z in anchor space): seated bodies lean
        // forward of the anchor origin, so this centers the gem over the head.
        entity.position = [0, SeatingLayout.seatedEyeHeight + baseY, -0.10]
        visible = true
    }

    /// Per-frame bob + spin + fade.
    func update(time: Double, dt: Double) {
        guard let opacity = entity.components[OpacityComponent.self]?.opacity else { return }
        let target: Float = visible ? 1 : 0
        if abs(opacity - target) > 0.01 {
            let alpha = Float(1 - exp(-dt / 0.15))
            entity.components.set(OpacityComponent(opacity: opacity + (target - opacity) * alpha))
        }
        guard visible else { return }
        let bob = Float(sin(time * 2 * .pi * 1.2)) * 0.03
        entity.position = [0, SeatingLayout.seatedEyeHeight + baseY + bob, -0.10]
        entity.orientation = simd_quatf(angle: Float(time * 0.9).truncatingRemainder(dividingBy: 2 * .pi), axis: [0, 1, 0])
    }
}
