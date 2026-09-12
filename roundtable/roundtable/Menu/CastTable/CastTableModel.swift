//
//  CastTableModel.swift
//  roundtable
//
//  Drag/roster state machine for the character-card table. Writes selection
//  back to AppModel.selectedCastIDs (single source of truth, shared with the
//  2D tile picker).
//

import Foundation
import Observation
import RealityKit
import simd

@MainActor
@Observable
final class CastTableModel {
    enum CardState: Equatable {
        case inTray(fanIndex: Int)
        case dragging
        case slotted(slotIndex: Int)
    }

    private(set) var cardStates: [String: CardState] = [:]
    /// slot index -> character id
    private(set) var slots: [Int: String] = [:]
    let slotCount = 5

    weak var appModel: AppModel?

    var seatedCount: Int { slots.count }

    func configure(characterIDs: [String], appModel: AppModel) {
        self.appModel = appModel
        var fan = 0
        cardStates = [:]
        slots = [:]
        for id in characterIDs {
            if id == "elowen" {
                // Moderator pre-seated and locked at slot 0.
                cardStates[id] = .slotted(slotIndex: 0)
                slots[0] = id
            } else if appModel.selectedCastIDs.contains(id), let free = firstFreeSlot() {
                cardStates[id] = .slotted(slotIndex: free)
                slots[free] = id
            } else {
                cardStates[id] = .inTray(fanIndex: fan)
                fan += 1
            }
        }
        syncSelection()
    }

    private func firstFreeSlot() -> Int? {
        (0..<slotCount).first { slots[$0] == nil }
    }

    func beginDrag(_ id: String) {
        guard id != "elowen" else { return }
        if case .slotted(let slot) = cardStates[id] {
            slots.removeValue(forKey: slot)
        }
        cardStates[id] = .dragging
    }

    /// Resolves a drop at `position` (tableRoot space). Returns the state the
    /// card should animate to.
    func resolveDrop(_ id: String, at position: SIMD3<Float>,
                     slotPositions: [SIMD3<Float>], tableRadius: Float) -> CardState {
        defer { syncSelection() }
        let planar = SIMD2<Float>(position.x, position.z)

        // Nearest free slot within snap radius.
        var best: (index: Int, distance: Float)?
        for (index, slotPos) in slotPositions.enumerated() where slots[index] == nil {
            let d = simd_distance(planar, SIMD2<Float>(slotPos.x, slotPos.z))
            if d < 0.06, d < (best?.distance ?? .infinity) {
                best = (index, d)
            }
        }
        if let best {
            slots[best.index] = id
            cardStates[id] = .slotted(slotIndex: best.index)
            return cardStates[id]!
        }

        // Otherwise back to the tray.
        let fanIndex = nextFanIndex()
        cardStates[id] = .inTray(fanIndex: fanIndex)
        return cardStates[id]!
    }

    /// Tap fallback (simulator/accessibility): toggles tray<->first-free-slot.
    func toggle(_ id: String, slotPositions: [SIMD3<Float>]) -> CardState? {
        guard id != "elowen" else { return nil }
        defer { syncSelection() }
        switch cardStates[id] {
        case .slotted(let slot):
            slots.removeValue(forKey: slot)
            cardStates[id] = .inTray(fanIndex: nextFanIndex())
        default:
            guard let free = firstFreeSlot() else { return nil }
            slots[free] = id
            cardStates[id] = .slotted(slotIndex: free)
        }
        return cardStates[id]
    }

    private func nextFanIndex() -> Int {
        let taken = cardStates.values.compactMap { state -> Int? in
            if case .inTray(let i) = state { return i }
            return nil
        }
        return (taken.max() ?? -1) + 1
    }

    private func syncSelection() {
        appModel?.selectedCastIDs = Set(slots.values)
    }
}
