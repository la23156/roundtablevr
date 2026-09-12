//
//  CastTableScene.swift
//  roundtable
//
//  Layout math + static entities for the card table volume: a small oval
//  wooden slab with 5 seat slots (mirroring the real table's arc) and a
//  fanned card tray facing the user.
//

import Foundation
import RealityKit
import UIKit

@MainActor
enum CastTableScene {
    // Volume is 0.9 x 0.55 x 0.55 m; keep ~10% margin.
    static let tableTopY: Float = -0.12          // slab top in tableRoot space
    static let hoverLift: Float = 0.025
    static let slabSemiX: Float = 0.20
    static let slabSemiZ: Float = 0.15

    /// Seat-slot positions on the slab (tableRoot space), mirroring
    /// SeatingLayout's arc: slot 0 = moderator at the far center.
    static func slotPositions() -> [SIMD3<Float>] {
        let seats = SeatingLayout.characterSeats(count: 5)
        return seats.map { seat in
            // Real seats live on an ellipse around tableCenter; normalize into
            // slab space (scale by slab/real semi-axes).
            let rel = seat.position - SeatingLayout.tableCenter
            let x = rel.x / (SeatingLayout.tableSemiX + SeatingLayout.seatSetback) * (slabSemiX * 0.72)
            let z = rel.z / (SeatingLayout.tableSemiZ + SeatingLayout.seatSetback) * (slabSemiZ * 0.72)
            return SIMD3<Float>(x, tableTopY + 0.002, z)
        }
    }

    /// Fanned tray transform for fan index `i` of `n` cards.
    static func trayTransform(fanIndex i: Int, of n: Int) -> Transform {
        let spread = 7 * Float.pi / 180
        let theta = (Float(i) - Float(max(n - 1, 1)) / 2) * spread
        let radius: Float = 0.35
        // In front of and slightly below the slab edge so standing cards
        // never intersect it.
        let pivot = SIMD3<Float>(0, tableTopY + 0.02, slabSemiZ + 0.11)
        let position = pivot + SIMD3<Float>(sin(theta) * radius * 0.55, abs(theta) * -0.01, cos(theta) * 0.02 + Float(i) * 0.0008)
        let backTilt = simd_quatf(angle: -25 * .pi / 180, axis: [1, 0, 0])
        let roll = simd_quatf(angle: -theta, axis: [0, 0, 1])
        return Transform(scale: .one, rotation: roll * backTilt, translation: position)
    }

    /// Flat-on-slab transform for a slot.
    static func slotTransform(_ index: Int) -> Transform {
        let p = slotPositions()[index]
        // Lie flat (face up), slight yaw toward slab center for a dealt look.
        let flat = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        let yaw = simd_quatf(angle: atan2(-p.x, -p.z) * 0.25, axis: [0, 1, 0])
        return Transform(scale: .one, rotation: yaw * flat, translation: SIMD3<Float>(p.x, p.y + 0.003, p.z))
    }

    /// Builds slab + slot decals. Returns (root, slotDecals).
    static func build() async -> (root: Entity, slotDecals: [ModelEntity]) {
        let root = Entity()
        root.name = "castTableRoot"
        root.position = [0, 0, -0.02]

        var slabMaterial = await EnvAssets.pbr("mocha_oak_veneer", tilesX: 2, tilesY: 2,
                                               fallbackTint: UIColor(red: 0.32, green: 0.20, blue: 0.11, alpha: 1))
        // Volumes use system lighting, which washes the veneer out — darken.
        slabMaterial.baseColor.tint = UIColor(red: 0.45, green: 0.30, blue: 0.17, alpha: 1)
        let slab = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: 1), materials: [slabMaterial])
        slab.scale = [slabSemiX, 1, slabSemiZ]
        slab.position = [0, tableTopY - 0.01, 0]
        root.addChild(slab)

        var decals: [ModelEntity] = []
        var decalMaterial = UnlitMaterial(color: UIColor(white: 1, alpha: 0.16))
        decalMaterial.blending = .transparent(opacity: 0.16)
        for position in slotPositions() {
            let decal = ModelEntity(
                mesh: .generatePlane(width: CharacterCardFactory.cardWidth + 0.01,
                                     height: CharacterCardFactory.cardHeight + 0.01,
                                     cornerRadius: 0.006),
                materials: [decalMaterial]
            )
            decal.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            decal.position = position
            root.addChild(decal)
            decals.append(decal)
        }
        return (root, decals)
    }
}
