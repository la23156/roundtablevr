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
import SwiftUI
import UIKit
import simd

@MainActor
final class HarknessOverlay {
    let root = Entity()

    private var orbs: [ModelEntity] = []
    private var edgeEntities: [ModelEntity] = []
    private let maxEdges = 12

    // Teacher's crib notes on the table: one strip per realization node.
    private var noteHolders: [Entity] = []
    private var noteStrips: [ModelEntity] = []
    private var noteGlows: [ModelEntity] = []
    private var noteCards: [NodeCard] = []
    private var noteHit: [Bool] = []
    /// Per-node pulse intensity 0-1 (driven by the director's node_closeness).
    private var noteCloseness: [Float] = []
    /// Gaze focus: which card is expanded with its coaching panel.
    private(set) var focusedNote: Int?   // 0-based
    private var detailPanels: [Int: Entity] = [:]
    private let noteTilt: Float = 0.95   // ~54°: faces a seated eye looking down
    /// Debug: lift coaching panels into the fixed simulator camera's view.
    var debugRaisePanels = false
    /// Debug: lift the post-it arc itself into the camera's view.
    var debugLiftNotes = false

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

    // MARK: - Teacher's desk notes (the crib sheet)

    /// Lays the condensed realization labels on the table in front of the
    /// teacher as small parchment strips. Only the teacher's side of the
    /// table — this is their private crib sheet, in easy glancing range.
    /// Lays the realization cards on the table as POST-IT NOTES in a wide
    /// horizontal arc at the teacher's edge. Spreading them in X (~22 cm
    /// apart ≈ 15° at arm's length) is what makes head-gaze targeting
    /// reliable — the old stacked column separated cards by only ~4°.
    func buildTeacherNotes(cards: [NodeCard]) async {
        noteCards = cards
        noteHit = Array(repeating: false, count: cards.count)
        noteCloseness = Array(repeating: 0, count: cards.count)
        let side: Float = 0.15
        let spacing: Float = 0.23
        let arcWidth = spacing * Float(cards.count - 1)
        // Hand-stuck feel: each note sits at a slightly different angle.
        let jitterYaw: [Float] = [-0.07, 0.05, -0.04, 0.07, -0.05]
        let tilt = simd_quatf(angle: noteTilt, axis: [1, 0, 0])
        for (i, card) in cards.enumerated() {
            let x = -arcWidth / 2 + Float(i) * spacing
            let holder = Entity()
            // Slight curve so the outer notes follow the table edge.
            let z: Float = -0.76 + 0.05 * (x * x) / 0.2
            if debugLiftNotes {
                holder.position = [x * 1.6, 1.15, -1.5]
                holder.orientation = simd_quatf(angle: jitterYaw[i % jitterYaw.count], axis: [0, 1, 0])
                    * simd_quatf(angle: 0.12, axis: [1, 0, 0])
            } else {
                holder.position = [x, SeatingLayout.tableTopHeight + 0.062, z]
                holder.orientation = simd_quatf(angle: jitterYaw[i % jitterYaw.count], axis: [0, 1, 0]) * tilt
            }
            root.addChild(holder)
            noteHolders.append(holder)

            // Amber glow pad behind the note: pulses as the class closes in.
            var glowMat = UnlitMaterial()
            glowMat.color = .init(tint: UIColor(red: 1.0, green: 0.72, blue: 0.2, alpha: 1))
            let glow = ModelEntity(mesh: .generatePlane(width: side + 0.03, depth: side + 0.03,
                                                        cornerRadius: 0.015),
                                   materials: [glowMat])
            glow.position = [0, -0.0015, 0]
            glow.components.set(OpacityComponent(opacity: 0))
            holder.addChild(glow)
            noteGlows.append(glow)

            let note = ModelEntity(mesh: .generatePlane(width: side, depth: side,
                                                        cornerRadius: 0.003),
                                   materials: [await Self.noteMaterial(index: i + 1, label: card.label,
                                                                       hit: false)])
            note.position = [0, 0.0005, 0]
            holder.addChild(note)
            noteStrips.append(note)
        }
    }

    /// Intro flourish: each post-it flashes amber in turn ("these are your
    /// targets"), then fades.
    func sweepNotes() {
        for (i, glow) in noteGlows.enumerated() {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(380 * i))
                glow.components.set(OpacityComponent(opacity: 0.85))
                for step in 0..<16 {
                    try? await Task.sleep(for: .milliseconds(55))
                    glow.components.set(OpacityComponent(opacity: 0.85 * (1 - Float(step) / 15)))
                }
                glow.components.set(OpacityComponent(opacity: 0))
            }
        }
    }

    // MARK: - Catalyst board (tutorial: the teacher launches the discussion)

    private var catalystPanel: Entity?

    /// Floats the catalyst options in front of the teacher: read one aloud
    /// (or improvise) to launch the discussion.
    func showCatalyst(options: [String]) {
        hideCatalyst()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let renderer = ImageRenderer(content: CatalystBoardView(options: options))
            renderer.scale = 2
            var material = UnlitMaterial()
            if let cg = renderer.cgImage,
               let texture = try? await TextureResource(image: cg, options: .init(semantic: .color)) {
                material.color = .init(texture: .init(texture))
            } else {
                material.color = .init(tint: UIColor(white: 0.1, alpha: 0.95))
            }
            let panel = ModelEntity(mesh: .generatePlane(width: 0.78, height: 0.78 * 0.62,
                                                         cornerRadius: 0.015),
                                    materials: [material])
            panel.position = [0, 1.32, -1.5]
            panel.orientation = simd_quatf(angle: 0.08, axis: [1, 0, 0])
            root.addChild(panel)
            catalystPanel = panel
        }
    }

    func hideCatalyst() {
        catalystPanel?.removeFromParent()
        catalystPanel = nil
    }

    /// World positions of the card strips (gaze targets for focus).
    var noteFocusTargets: [SIMD3<Float>] {
        noteHolders.map { $0.position(relativeTo: nil) }
    }

    /// Teacher is looking at card `index` (0-based; nil = none): the card
    /// swells slightly and its coaching panel unfolds above the crib sheet.
    func setFocusedNote(_ index: Int?) {
        guard index != focusedNote else { return }
        // Collapse the old one.
        if let old = focusedNote, noteHolders.indices.contains(old) {
            var t = noteHolders[old].transform
            t.scale = SIMD3<Float>(repeating: 1)
            noteHolders[old].move(to: t, relativeTo: noteHolders[old].parent,
                                  duration: 0.18, timingFunction: .easeOut)
            detailPanels[old]?.isEnabled = false
        }
        focusedNote = index
        guard let index, noteHolders.indices.contains(index) else { return }
        var t = noteHolders[index].transform
        t.scale = SIMD3<Float>(repeating: 1.15)
        noteHolders[index].move(to: t, relativeTo: noteHolders[index].parent,
                                duration: 0.18, timingFunction: .easeOut)
        if let panel = detailPanels[index] {
            panel.isEnabled = true
        } else {
            let slot = index
            Task { @MainActor [weak self] in
                guard let self, noteCards.indices.contains(slot) else { return }
                let panel = await Self.makeDetailPanel(index: slot + 1, card: noteCards[slot])
                // Unfolds just above ITS post-it (pulled toward center so the
                // outer notes' panels stay on the table).
                if debugRaisePanels {
                    panel.position = [0, 1.45, -1.7]
                    panel.orientation = simd_quatf(angle: 0.1, axis: [1, 0, 0])
                } else {
                    let noteX = noteHolders.indices.contains(slot)
                        ? noteHolders[slot].position.x : 0
                    panel.position = [noteX * 0.65, SeatingLayout.tableTopHeight + 0.30, -0.97]
                    panel.orientation = simd_quatf(angle: 0.5, axis: [1, 0, 0])
                }
                root.addChild(panel)
                detailPanels[slot] = panel
                panel.isEnabled = focusedNote == slot
            }
        }
    }

    /// The coaching panel: label + "how to question them there".
    private static func makeDetailPanel(index: Int, card: NodeCard) async -> Entity {
        let renderer = ImageRenderer(content: NoteDetailView(index: index, card: card))
        renderer.scale = 2
        var material = UnlitMaterial()
        if let cg = renderer.cgImage,
           let texture = try? await TextureResource(image: cg, options: .init(semantic: .color)) {
            material.color = .init(texture: .init(texture))
        } else {
            material.color = .init(tint: UIColor(white: 0.1, alpha: 0.9))
        }
        let panel = ModelEntity(mesh: .generatePlane(width: 0.46, height: 0.46 * 0.56,
                                                     cornerRadius: 0.012),
                                materials: [material])
        return panel
    }

    /// The director says the thread is `closeness` (0-1) from landing node
    /// `index` (1-based). Other uncovered nodes cool off.
    func setCloseness(node index: Int?, closeness: Double) {
        for i in noteCloseness.indices {
            if noteHit[i] {
                noteCloseness[i] = 0
            } else if let index, i == index - 1 {
                noteCloseness[i] = Float(min(max(closeness, 0), 1))
            } else {
                noteCloseness[i] *= 0.35   // cool, don't snap: threads meander
            }
        }
    }

    /// Node landed: green flash, label crossed out, pulse retired.
    func markNoteHit(_ index: Int) {
        let i = index - 1
        guard noteStrips.indices.contains(i), !noteHit[i] else { return }
        noteHit[i] = true
        noteCloseness[i] = 0
        let strip = noteStrips[i]
        let label = noteCards.indices.contains(i) ? noteCards[i].label : ""
        Task { @MainActor in
            strip.model?.materials = [await Self.noteMaterial(index: index, label: label, hit: true)]
        }
        // Green burst on the glow pad, fading out over ~2 s.
        var mat = UnlitMaterial()
        mat.color = .init(tint: UIColor(red: 0.2, green: 0.95, blue: 0.4, alpha: 1))
        noteGlows[i].model?.materials = [mat]
        noteGlows[i].components.set(OpacityComponent(opacity: 0.9))
        Task { @MainActor [weak self] in
            guard let self else { return }
            for step in 0..<40 {
                try? await Task.sleep(for: .milliseconds(50))
                noteGlows[i].components.set(OpacityComponent(opacity: 0.9 * (1 - Float(step) / 39)))
            }
        }
    }

    /// Per-frame: pulse the glow pads under notes the class is closing in on.
    func update(time: Double) {
        for i in noteGlows.indices where !noteHit[i] {
            let closeness = noteCloseness[i]
            guard closeness > 0.05 else {
                noteGlows[i].components.set(OpacityComponent(opacity: 0))
                continue
            }
            // Stronger + faster pulse as the discussion gets closer.
            let rate = 1.5 + Double(closeness) * 3.5
            let wave = Float(0.5 + 0.5 * sin(time * rate))
            noteGlows[i].components.set(OpacityComponent(opacity: closeness * (0.25 + 0.55 * wave)))
        }
    }

    /// Renders one crib strip: numbered label on parchment; hit strips go
    /// green-tinted with a strikethrough and a check.
    private static func noteMaterial(index: Int, label: String, hit: Bool) async -> PhysicallyBasedMaterial {
        let renderer = ImageRenderer(content: NoteStripView(index: index, label: label, hit: hit))
        renderer.scale = 2
        var material = PhysicallyBasedMaterial()
        material.roughness = .init(floatLiteral: 0.85)
        if let cg = renderer.cgImage,
           let texture = try? await TextureResource(image: cg, options: .init(semantic: .color)) {
            material.baseColor = .init(texture: .init(texture))
        } else {
            material.baseColor = .init(tint: hit ? .systemGreen : UIColor(red: 0.94, green: 0.89, blue: 0.78, alpha: 1))
        }
        return material
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

/// One post-it on the table: a square sticky note with a hand-written
/// realization label. Goes green with a strikethrough and a check once the
/// class lands it.
private struct NoteStripView: View {
    let index: Int
    let label: String
    let hit: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(index)")
                    .font(.custom("Noteworthy-Bold", size: 42))
                    .foregroundStyle(hit ? Color.green : Color(red: 0.5, green: 0.33, blue: 0.08))
                Spacer()
                if hit {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "eye")
                        .font(.system(size: 24))
                        .foregroundStyle(Color(red: 0.55, green: 0.42, blue: 0.1).opacity(0.55))
                }
            }
            Spacer(minLength: 0)
            Text(label)
                .font(.custom("Noteworthy-Bold", size: 44))
                .strikethrough(hit, color: .green)
                .foregroundStyle(hit ? Color(white: 0.4) : Color(red: 0.13, green: 0.09, blue: 0.02))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.5)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 340, height: 340)
        .background(
            ZStack(alignment: .top) {
                // Classic sticky-note yellow (greened once hit) with a
                // slightly darker adhesive strip along the top edge.
                Rectangle()
                    .fill(hit ? Color(red: 0.8, green: 0.93, blue: 0.75)
                              : Color(red: 1.0, green: 0.95, blue: 0.55))
                Rectangle()
                    .fill(Color.black.opacity(0.07))
                    .frame(height: 34)
            }
        )
    }
}

/// The floating catalyst board: three ways to launch the discussion, read
/// aloud in the teacher's own voice (or improvised).
private struct CatalystBoardView: View {
    let options: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LAUNCH THE DISCUSSION")
                .font(.system(size: 15, weight: .bold))
                .kerning(3)
                .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.4))
            Text("Read ONE aloud, in your own voice — or ask your own version.")
                .font(.system(size: 21, weight: .semibold, design: .serif))
                .foregroundStyle(Color(red: 0.96, green: 0.91, blue: 0.8))
            ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.system(size: 22, weight: .heavy, design: .serif))
                        .foregroundStyle(Color(red: 0.45, green: 0.75, blue: 0.85))
                    Text("“\(option)”")
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("…then lean back, look at your notes, and say nothing.")
                .font(.system(size: 18, weight: .regular, design: .serif).italic())
                .foregroundStyle(Color(red: 0.7, green: 0.62, blue: 0.48))
        }
        .padding(26)
        .frame(width: 820, height: 508, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.11, green: 0.07, blue: 0.03).opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color(red: 0.95, green: 0.78, blue: 0.4).opacity(0.7), lineWidth: 2)
        )
    }
}

/// The coaching panel that unfolds when the teacher looks at a crib card:
/// how to QUESTION the class toward this realization, never the answer.
private struct NoteDetailView: View {
    let index: Int
    let card: NodeCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(index)")
                    .font(.system(size: 26, weight: .heavy, design: .serif))
                    .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.4))
                Text(card.label)
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(Color(red: 0.96, green: 0.91, blue: 0.8))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            Rectangle()
                .fill(Color(red: 0.95, green: 0.78, blue: 0.4).opacity(0.5))
                .frame(height: 2)
            Text("STEER THEM THERE WITH QUESTIONS")
                .font(.system(size: 13, weight: .bold))
                .kerning(2)
                .foregroundStyle(Color(red: 0.7, green: 0.62, blue: 0.48))
            ForEach(Array(card.coaching.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "questionmark.bubble.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(red: 0.45, green: 0.75, blue: 0.85))
                    Text(line)
                        .font(.system(size: 19, weight: .semibold, design: .serif))
                        .foregroundStyle(Color(red: 0.9, green: 0.87, blue: 0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 620, height: 348, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.11, green: 0.07, blue: 0.03).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(red: 0.95, green: 0.78, blue: 0.4).opacity(0.7), lineWidth: 2)
        )
    }
}
