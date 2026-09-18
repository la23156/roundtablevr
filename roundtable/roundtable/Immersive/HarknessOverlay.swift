//
//  HarknessOverlay.swift
//  roundtable
//
//  HarknessAI in-scene augmentation: the Conversation Web (glowing lines on
//  the tabletop between consecutive speakers — blue when students talk to
//  each other, red when the flow bounces through the teacher) and the
//  Guideflow Tracker (dim orbs above the table center that turn gold as the
//  class organically reaches each realization node).
//

import RealityKit
import UIKit
import simd

@MainActor
final class HarknessOverlay {
    let root = Entity()

    private var orbs: [ModelEntity] = []
    private var edgeEntities: [ModelEntity] = []
    private let maxEdges = 12

    // Inset ellipse on the tabletop where web endpoints land.
    private let edgeA = SeatingLayout.tableSemiX - 0.22
    private let edgeB = SeatingLayout.tableSemiZ - 0.22
    private let webY = SeatingLayout.tableTopHeight + 0.006

    init(nodeCount: Int) {
        root.name = "HarknessOverlay"
        buildOrbs(count: nodeCount)
    }

    // MARK: - Guideflow orbs

    private func buildOrbs(count: Int) {
        guard count > 0 else { return }
        let spacing: Float = 0.22
        let width = spacing * Float(count - 1)
        for i in 0..<count {
            var material = PhysicallyBasedMaterial()
            let dim = UIColor(white: 0.55, alpha: 1)
            material.baseColor = .init(tint: dim)
            material.emissiveColor = .init(color: dim)
            material.emissiveIntensity = 0.25
            material.roughness = .init(floatLiteral: 0.3)
            let orb = ModelEntity(mesh: .generateSphere(radius: 0.035), materials: [material])
            orb.position = SeatingLayout.tableCenter + SIMD3<Float>(
                -width / 2 + Float(i) * spacing,
                SeatingLayout.tableTopHeight + 0.55,
                0)
            root.addChild(orb)
            orbs.append(orb)
        }
    }

    /// The class just reached realization node `index` (1-based): the orb
    /// lights gold with a little swell.
    func markNodeCovered(_ index: Int) {
        let i = index - 1
        guard orbs.indices.contains(i) else { return }
        let orb = orbs[i]
        var material = PhysicallyBasedMaterial()
        let gold = UIColor(red: 1.0, green: 0.82, blue: 0.25, alpha: 1)
        material.baseColor = .init(tint: gold)
        material.emissiveColor = .init(color: gold)
        material.emissiveIntensity = 2.0
        material.roughness = .init(floatLiteral: 0.15)
        orb.model?.materials = [material]

        // Swell-and-settle pulse.
        let basePos = orb.position
        var swelled = orb.transform
        swelled.scale = SIMD3<Float>(repeating: 1.8)
        swelled.translation = basePos + SIMD3<Float>(0, 0.04, 0)
        orb.move(to: swelled, relativeTo: orb.parent, duration: 0.35, timingFunction: .easeOut)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            var settled = orb.transform
            settled.scale = SIMD3<Float>(repeating: 1.15)
            settled.translation = basePos
            orb.move(to: settled, relativeTo: orb.parent, duration: 0.5, timingFunction: .easeInOut)
        }
    }

    // MARK: - Conversation web

    /// Adds a glowing chord on the tabletop from the previous speaker's edge
    /// point to the current one. Teacher-touching edges glow red (starburst
    /// warning), student-student edges glow blue.
    func addEdge(from: SIMD3<Float>, to: SIMD3<Float>, involvesTeacher: Bool) {
        let a = tableEdgePoint(nearest: from)
        let b = tableEdgePoint(nearest: to)
        let delta = b - a
        let length = simd_length(SIMD3<Float>(delta.x, 0, delta.z))
        guard length > 0.05 else { return }

        var material = UnlitMaterial()
        let color = involvesTeacher
            ? UIColor(red: 0.95, green: 0.28, blue: 0.2, alpha: 1)
            : UIColor(red: 0.25, green: 0.62, blue: 1.0, alpha: 1)
        material.color = .init(tint: color)

        let bar = ModelEntity(mesh: .generateBox(size: [length, 0.0025, 0.010], cornerRadius: 0.001),
                              materials: [material])
        bar.position = SIMD3<Float>((a.x + b.x) / 2, webY, (a.z + b.z) / 2)
        bar.orientation = simd_quatf(angle: atan2(-delta.z, delta.x), axis: [0, 1, 0])
        root.addChild(bar)
        edgeEntities.append(bar)

        // Older strands fade so the web reads as "recent flow", not clutter.
        let n = edgeEntities.count
        for (i, entity) in edgeEntities.enumerated() {
            let age = n - 1 - i
            entity.components.set(OpacityComponent(opacity: max(0.12, 1.0 - Float(age) * 0.12)))
        }
        while edgeEntities.count > maxEdges {
            edgeEntities.removeFirst().removeFromParent()
        }
    }

    /// Projects any seat/head position onto an inset ellipse on the tabletop.
    private func tableEdgePoint(nearest position: SIMD3<Float>) -> SIMD3<Float> {
        let v = SIMD3<Float>(position.x, 0, position.z) - SeatingLayout.tableCenter
        let vx = v.x, vz = v.z
        let denom = sqrt((vx / edgeA) * (vx / edgeA) + (vz / edgeB) * (vz / edgeB))
        guard denom > 0.0001 else {
            return SeatingLayout.tableCenter + SIMD3<Float>(0, webY, edgeB)
        }
        let t = 1 / denom
        return SeatingLayout.tableCenter + SIMD3<Float>(vx * t, webY, vz * t)
    }
}
