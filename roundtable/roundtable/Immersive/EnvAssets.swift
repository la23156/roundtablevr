//
//  EnvAssets.swift
//  roundtable
//
//  Loads environment USDZs and PBR texture sets bundled in EnvAssets/.
//

import Foundation
import RealityKit
import UIKit

@MainActor
enum EnvAssets {

    static func model(_ name: String) async -> Entity? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz") else {
            print("EnvAssets: missing \(name).usdz")
            return nil
        }
        return try? await Entity(contentsOf: url)
    }

    /// Loads `<base>_diffuse/_nor/_rough.jpg` into a tiled PBR material.
    /// Falls back to a flat tint if textures are missing.
    static func pbr(_ base: String, tilesX: Float, tilesY: Float,
                    fallbackTint: UIColor) async -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.metallic = .init(floatLiteral: 0)

        func texture(_ suffix: String, semantic: TextureResource.Semantic) async -> MaterialParameters.Texture? {
            guard let url = Bundle.main.url(forResource: "\(base)_\(suffix)", withExtension: "jpg") else { return nil }
            guard let resource = try? await TextureResource(
                contentsOf: url,
                options: .init(semantic: semantic)
            ) else { return nil }
            return MaterialParameters.Texture(resource)
        }

        if let diffuse = await texture("diffuse", semantic: .color) {
            material.baseColor = .init(tint: .white, texture: diffuse)
        } else {
            material.baseColor = .init(tint: fallbackTint)
        }
        if let normal = await texture("nor", semantic: .normal) {
            material.normal = .init(texture: normal)
        }
        if let rough = await texture("rough", semantic: .scalar) {
            material.roughness = .init(scale: 1, texture: rough)
        } else {
            material.roughness = .init(floatLiteral: 0.75)
        }
        material.textureCoordinateTransform = .init(scale: SIMD2<Float>(tilesX, tilesY))
        return material
    }

    /// Grounds an entity: uniform-scales it to `height` (if given) and offsets
    /// it so its bounds bottom sits on y=0 and its center on the pivot.
    static func ground(_ entity: Entity, height: Float? = nil) {
        var bounds = entity.visualBounds(relativeTo: nil)
        if let height, bounds.extents.y > 0.001 {
            let factor = height / bounds.extents.y
            entity.scale *= SIMD3<Float>(repeating: factor)
            bounds = entity.visualBounds(relativeTo: nil)
        }
        entity.position.y -= bounds.min.y
        entity.position.x -= bounds.center.x
        entity.position.z -= bounds.center.z
    }

    /// Wraps a grounded model in a container so callers can place the
    /// container without fighting the model's own pivot.
    static func placed(_ entity: Entity, height: Float? = nil,
                       at position: SIMD3<Float>, yaw: Float = 0) -> Entity {
        let container = Entity()
        ground(entity, height: height)
        container.addChild(entity)
        container.position = position
        container.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        return container
    }
}
