//
//  CharacterCard.swift
//  roundtable
//
//  3D character cards: poker-card-sized rounded planes, face texture
//  pre-composed by SwiftUI ImageRenderer (portrait + parchment name plate),
//  shared ornate back. Identity carried by CardComponent.
//

import Foundation
import RealityKit
import SwiftUI
import UIKit

struct CardComponent: Component {
    let characterID: String
    let locked: Bool
}

/// The SwiftUI view rendered into each card's face texture.
struct CardFaceView: View {
    let spec: CharacterSpec
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
                        .font(.system(size: 130, weight: .bold, design: .serif))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(UIColor(spec.tint).swiftUIColor.opacity(0.55))
                }
            }
            .frame(width: 378, height: 372)
            .clipped()

            VStack(spacing: 3) {
                Text(spec.name)
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .foregroundStyle(Color(red: 0.20, green: 0.13, blue: 0.06))
                Text(spec.archetype.uppercased())
                    .font(.system(size: 20, weight: .semibold))
                    .kerning(2)
                    .foregroundStyle(spec.tint)
                if spec.isModerator {
                    Text("MODERATOR")
                        .font(.system(size: 16, weight: .heavy))
                        .kerning(1.5)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(spec.tint.opacity(0.85)))
                        .foregroundStyle(.white)
                }
            }
            .padding(.vertical, 12)
            .frame(width: 378, height: 156)
            .background(Color(red: 0.91, green: 0.85, blue: 0.72))   // parchment
        }
        .frame(width: 378, height: 528)                              // 63x88 ratio
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(spec.tint.opacity(0.9), lineWidth: 7)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private var initials: String {
        spec.name.split(separator: " ").compactMap(\.first).suffix(2).map(String.init).joined()
    }
}

private extension UIColor {
    var swiftUIColor: Color { Color(self) }
}

@MainActor
enum CharacterCardFactory {
    static let cardWidth: Float = 0.063
    static let cardHeight: Float = 0.088

    private static var backTexture: TextureResource?
    private static var faceCache: [String: TextureResource] = [:]

    /// Builds a card entity for `spec`. Portrait resolution order:
    /// bundled CardArt/<id>.jpg -> remote URL -> monogram fallback.
    static func makeCard(spec: CharacterSpec, portraitURL: URL?, locked: Bool) async -> Entity {
        let faceMesh = MeshResource.generatePlane(
            width: cardWidth, height: cardHeight, cornerRadius: 0.005)

        let root = Entity()
        root.name = "card_\(spec.id)"

        let face = await faceTexture(for: spec, portraitURL: portraitURL)
        var frontMaterial = PhysicallyBasedMaterial()
        frontMaterial.baseColor = .init(tint: .white, texture: .init(face))
        frontMaterial.roughness = .init(floatLiteral: 0.55)
        frontMaterial.metallic = .init(floatLiteral: 0)
        let front = ModelEntity(mesh: faceMesh, materials: [frontMaterial])
        front.position.z = 0.0008
        root.addChild(front)

        if let back = await sharedBackTexture() {
            var backMaterial = PhysicallyBasedMaterial()
            backMaterial.baseColor = .init(tint: .white, texture: .init(back))
            backMaterial.roughness = .init(floatLiteral: 0.55)
            let backEntity = ModelEntity(mesh: faceMesh, materials: [backMaterial])
            backEntity.position.z = -0.0008
            backEntity.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
            root.addChild(backEntity)
        }

        root.components.set(CardComponent(characterID: spec.id, locked: locked))
        if !locked {
            root.components.set(InputTargetComponent(allowedInputTypes: [.indirect, .direct]))
            root.components.set(HoverEffectComponent(.spotlight(.init(color: .white, strength: 0.4))))
        }
        root.components.set(CollisionComponent(shapes: [
            .generateBox(width: cardWidth + 0.012, height: cardHeight + 0.012, depth: 0.015)
        ]))
        root.components.set(GroundingShadowComponent(castsShadow: true))
        return root
    }

    // MARK: - Textures

    private static func faceTexture(for spec: CharacterSpec, portraitURL: URL?) async -> TextureResource {
        if let cached = faceCache[spec.id] { return cached }
        let portrait = await loadPortrait(spec: spec, url: portraitURL)
        let renderer = ImageRenderer(content: CardFaceView(spec: spec, portrait: portrait))
        renderer.scale = 2
        renderer.isOpaque = true
        let cg = renderer.uiImage?.cgImage ?? Self.solidFallback(tint: UIColor(spec.tint))
        var texture = try? await TextureResource(image: cg, options: .init(semantic: .color))
        if texture == nil {
            texture = try? await TextureResource(image: Self.solidFallback(tint: .brown),
                                                 options: .init(semantic: .color))
        }
        let resolved = texture!
        faceCache[spec.id] = resolved
        return resolved
    }

    private static func loadPortrait(spec: CharacterSpec, url: URL?) async -> UIImage? {
        if let bundled = Bundle.main.url(forResource: spec.id, withExtension: "jpg"),
           let image = UIImage(contentsOfFile: bundled.path) {
            return image
        }
        if let url,
           let (data, response) = try? await URLSession.shared.data(from: url),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }

    private static func sharedBackTexture() async -> TextureResource? {
        if let backTexture { return backTexture }
        guard let url = Bundle.main.url(forResource: "card_back", withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
        backTexture = try? await TextureResource(image: image, options: .init(semantic: .color))
        return backTexture
    }

    private static func solidFallback(tint: UIColor) -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 90))
        return renderer.image { ctx in
            tint.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 90))
        }.cgImage!
    }
}
