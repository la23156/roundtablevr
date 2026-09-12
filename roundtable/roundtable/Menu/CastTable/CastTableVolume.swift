//
//  CastTableVolume.swift
//  roundtable
//
//  The volumetric "build your table" window: drag character cards from the
//  fanned tray onto seat slots (or tap a card to toggle, which is also the
//  simulator/accessibility path). Selection syncs to AppModel.selectedCastIDs.
//

import RealityKit
import SwiftUI

struct CastTableVolume: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var model = CastTableModel()
    @State private var tableRoot: Entity?
    @State private var cards: [String: Entity] = [:]

    private struct DragState {
        let id: String
        let card: Entity
        let grabOffset: SIMD3<Float>
        var moved = false
    }
    @State private var dragState: DragState?

    var body: some View {
        RealityView { content in
            let (root, _) = await CastTableScene.build()
            content.add(root)
            tableRoot = root

            let store = appModel.characterStore
            let all = store.all
            model.configure(characterIDs: all.map(\.id), appModel: appModel)

            for spec in all {
                let card = await CharacterCardFactory.makeCard(
                    spec: spec,
                    portraitURL: store.portraitURLs[spec.id],
                    locked: spec.isModerator
                )
                root.addChild(card)
                cards[spec.id] = card
                place(card, state: model.cardStates[spec.id] ?? .inTray(fanIndex: 0), animated: false)
            }
        } update: { _ in
            // 2D picker changed the selection while the volume is open:
            // re-place any cards whose state disagrees.
            resyncFromSelection()
        }
        .gesture(dragGesture)
        .gesture(tapGesture)
        .ornament(attachmentAnchor: .scene(.bottom)) {
            HStack(spacing: 14) {
                Text("\(model.seatedCount) of \(model.slotCount) seated")
                    .font(.system(.headline, design: .serif))
                Button("Done") { dismissWindow(id: AppModel.castTableWindowID) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .glassBackgroundEffect()
        }
    }

    // MARK: - Gestures

    private var dragGesture: some SwiftUI.Gesture {
        DragGesture(minimumDistance: 0.004)
            .targetedToAnyEntity()
            .onChanged { value in
                guard let tableRoot else { return }
                guard let (id, card) = cardEntity(from: value.entity), cardIsDraggable(id) else { return }
                let finger = value.convert(value.location3D, from: .local, to: tableRoot)
                if dragState == nil {
                    model.beginDrag(id)
                    dragState = DragState(id: id, card: card,
                                          grabOffset: card.position(relativeTo: tableRoot) - finger)
                    card.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
                }
                dragState?.moved = true
                var target = finger + (dragState?.grabOffset ?? .zero)
                target.y = CastTableScene.tableTopY + CastTableScene.hoverLift
                card.setPosition(target, relativeTo: tableRoot)
            }
            .onEnded { _ in
                guard let state = dragState, let tableRoot else { dragState = nil; return }
                let dropPosition = state.card.position(relativeTo: tableRoot)
                let newState = model.resolveDrop(state.id, at: dropPosition,
                                                 slotPositions: CastTableScene.slotPositions(),
                                                 tableRadius: CastTableScene.slabSemiX)
                place(state.card, state: newState, animated: true)
                dragState = nil
            }
    }

    private var tapGesture: some SwiftUI.Gesture {
        TapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                guard dragState == nil,
                      let (id, card) = cardEntity(from: value.entity), cardIsDraggable(id),
                      let newState = model.toggle(id, slotPositions: CastTableScene.slotPositions())
                else { return }
                place(card, state: newState, animated: true)
            }
    }

    private func cardIsDraggable(_ id: String) -> Bool {
        cards[id]?.components[CardComponent.self]?.locked == false
    }

    private func cardEntity(from tapped: Entity) -> (String, Entity)? {
        var current: Entity? = tapped
        while let entity = current {
            if let component = entity.components[CardComponent.self] {
                return (component.characterID, entity)
            }
            current = entity.parent
        }
        return nil
    }

    // MARK: - Placement

    private func place(_ card: Entity, state: CastTableModel.CardState, animated: Bool) {
        let trayCount = max(appModel.characterStore.all.count - model.seatedCount, 1)
        let transform: Transform
        switch state {
        case .inTray(let fanIndex):
            transform = CastTableScene.trayTransform(fanIndex: fanIndex, of: trayCount)
        case .slotted(let slotIndex):
            transform = CastTableScene.slotTransform(slotIndex)
        case .dragging:
            return
        }
        if animated {
            card.move(to: transform, relativeTo: card.parent, duration: 0.28, timingFunction: .easeOut)
        } else {
            card.transform = transform
        }
    }

    private func resyncFromSelection() {
        guard dragState == nil else { return }
        let selected = appModel.selectedCastIDs
        for (id, card) in cards {
            let isSlotted: Bool
            if case .slotted = model.cardStates[id] { isSlotted = true } else { isSlotted = false }
            if selected.contains(id) != isSlotted, cardIsDraggable(id),
               let newState = model.toggle(id, slotPositions: CastTableScene.slotPositions()) {
                place(card, state: newState, animated: true)
            }
        }
    }
}
