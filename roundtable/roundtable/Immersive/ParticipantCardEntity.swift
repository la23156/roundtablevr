//
//  ParticipantCardEntity.swift
//  roundtable
//
//  iPhone guests have no Spatial Persona, so they appear at the table as a
//  card easel: a rounded plane with their chosen character portrait and name
//  (texture pre-composed with ImageRenderer, same trick as the cast cards in
//  Menu/CastTable/CharacterCard.swift), plus an emissive rim whose glow is
//  driven by the guest's live speakingLevel pulses.
//

import Foundation
import RealityKit
import SwiftUI
import UIKit

/// The SwiftUI view rendered into the guest card's face texture.
private struct GuestCardFaceView: View {
    let name: String
    let portrait: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(red: 0.16, green: 0.10, blue: 0.05)
                if let portrait {
                    Image(uiImage: portrait)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(initials)
                        .font(.system(size: 120, weight: .bold, design: .serif))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(red: 0.28, green: 0.42, blue: 0.55))
                }
            }
            .frame(width: 378, height: 380)
            .clipped()

            VStack(spacing: 4) {
                Text(name)
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(Color(red: 0.20, green: 0.13, blue: 0.06))
                Text("JOINING BY PHONE")
                    .font(.system(size: 17, weight: .semibold))
                    .kerning(2.2)
                    .foregroundStyle(Color(red: 0.45, green: 0.35, blue: 0.2))
            }
            .padding(.vertical, 14)
            .frame(width: 378, height: 148)
            .background(Color(red: 0.91, green: 0.85, blue: 0.72))   // parchment
        }
        .frame(width: 378, height: 528)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color(red: 0.36, green: 0.62, blue: 0.86).opacity(0.9), lineWidth: 7)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private var initials: String {
        name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined()
    }
}

@MainActor
final class ParticipantCardEntity: Entity {
    /// Card plane dimensions (a friendly head-and-shoulders scale).
    private static let cardWidth: Float = 0.34
    private static let cardHeight: Float = 0.475

    private var rim: ModelEntity?
    private var level: Float = 0

    /// Builds the easel: wooden post, glowing rim, and the composed card face
    /// at seated-head height so the guest "sits" at the table.
    static func make(name: String, characterID: String?) async -> ParticipantCardEntity {
        let entity = ParticipantCardEntity()
        entity.name = "guestCard_\(name)"

        // Easel post.
        var postMaterial = PhysicallyBasedMaterial()
        postMaterial.baseColor = .init(tint: UIColor(red: 0.42, green: 0.28, blue: 0.16, alpha: 1))
        postMaterial.roughness = .init(floatLiteral: 0.6)
        let post = ModelEntity(mesh: .generateCylinder(height: 0.9, radius: 0.02),
                               materials: [postMaterial])
        post.position = [0, 0.45, 0]
        entity.addChild(post)

        let faceCenterY = SeatingLayout.seatedEyeHeight - 0.1

        // Emissive rim (slightly larger plane behind the card).
        var rimMaterial = UnlitMaterial(color: UIColor(red: 0.36, green: 0.62, blue: 0.86, alpha: 1))
        rimMaterial.blending = .transparent(opacity: 0.0)
        let rim = ModelEntity(
            mesh: .generatePlane(width: cardWidth + 0.035, height: cardHeight + 0.035, cornerRadius: 0.03),
            materials: [rimMaterial])
        rim.name = "GuestCardRim"
        rim.position = [0, faceCenterY, 0.006]
        entity.addChild(rim)
        entity.rim = rim

        // Card face.
        let portrait: UIImage? = characterID.flatMap { id in
            Bundle.main.url(forResource: id, withExtension: "jpg")
                .flatMap { UIImage(contentsOfFile: $0.path) }
        }
        let renderer = ImageRenderer(content: GuestCardFaceView(name: name, portrait: portrait))
        renderer.scale = 2
        renderer.isOpaque = true
        var faceMaterial = PhysicallyBasedMaterial()
        if let cg = renderer.uiImage?.cgImage,
           let texture = try? await TextureResource(image: cg, options: .init(semantic: .color)) {
            faceMaterial.baseColor = .init(tint: .white, texture: .init(texture))
        } else {
            faceMaterial.baseColor = .init(tint: UIColor(red: 0.36, green: 0.62, blue: 0.86, alpha: 1))
        }
        faceMaterial.roughness = .init(floatLiteral: 0.55)
        faceMaterial.metallic = .init(floatLiteral: 0)
        let face = ModelEntity(
            mesh: .generatePlane(width: cardWidth, height: cardHeight, cornerRadius: 0.02),
            materials: [faceMaterial])
        face.name = "GuestCardFace"
        // The plane faces +Z; the anchor's -Z looks at the table, so flip it.
        face.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        rim.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        face.position = [0, faceCenterY, 0]
        entity.addChild(face)

        return entity
    }

    /// Speaking-level pulse from the unreliable messenger (0...1).
    func setLevel(_ newLevel: Float) {
        level = max(level, min(max(newLevel, 0), 1))
        applyGlow()
    }

    /// Called per-frame by SessionController: glow decays between pulses.
    func update(dt: Float) {
        guard level > 0.001 else { return }
        level = max(0, level - dt * 1.8)
        applyGlow()
    }

    private func applyGlow() {
        guard let rim else { return }
        var material = UnlitMaterial(color: UIColor(red: 0.36, green: 0.62, blue: 0.86, alpha: 1))
        material.blending = .transparent(opacity: .init(floatLiteral: Float(min(level, 1)) * 0.85))
        rim.model?.materials = [material]
    }
}
