//
//  LightingRig.swift
//  roundtable
//
//  Warm "antique study" lighting: a procedurally generated warm-interior IBL
//  plus two spotlights (tabletop, chalkboard wall). Full immersion means the
//  app provides every photon; without an IBL, PBR materials render black.
//

import RealityKit
import UIKit

enum LightingRig {

    /// Adds IBL + spotlights to `root` and makes every current descendant an
    /// IBL receiver. Call after scene geometry is in place.
    @MainActor
    static func install(on root: Entity) async throws {
        let ibl = try await interiorIBL()

        let lightSource = Entity()
        lightSource.name = "IBLSource"
        // Keep the IBL dim so the warm spotlights read as the light source —
        // that's where the antique-study mood comes from.
        lightSource.components.set(ImageBasedLightComponent(source: .single(ibl), intensityExponent: 0.25))
        root.addChild(lightSource)

        root.forEachDescendant { entity in
            if entity.components.has(ModelComponent.self) {
                entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: lightSource))
            }
        }

        // Warm pool of light over the tabletop.
        let tableSpot = Entity()
        tableSpot.name = "TableSpot"
        var spot = SpotLightComponent()
        spot.color = UIColor(red: 1.0, green: 0.85, blue: 0.66, alpha: 1)
        spot.intensity = 18_000
        spot.innerAngleInDegrees = 35
        spot.outerAngleInDegrees = 70
        spot.attenuationRadius = 6
        tableSpot.components.set(spot)
        tableSpot.position = SeatingLayout.tableCenter + SIMD3<Float>(0, 2.9, 0)
        tableSpot.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]) // aim straight down
        root.addChild(tableSpot)

        // Soft wash on the far (chalkboard) wall.
        let wallSpot = Entity()
        wallSpot.name = "WallSpot"
        var wash = SpotLightComponent()
        wash.color = UIColor(red: 1.0, green: 0.88, blue: 0.72, alpha: 1)
        wash.intensity = 6_000
        wash.innerAngleInDegrees = 50
        wash.outerAngleInDegrees = 90
        wash.attenuationRadius = 7
        wallSpot.components.set(wash)
        wallSpot.position = SeatingLayout.tableCenter + SIMD3<Float>(0, 3.0, -1.0)
        wallSpot.orientation = simd_quatf(angle: -.pi / 3, axis: [1, 0, 0])
        root.addChild(wallSpot)
    }

    /// Real interior HDRI when bundled; procedural warm gradient otherwise.
    @MainActor
    private static func interiorIBL() async throws -> EnvironmentResource {
        if let url = Bundle.main.url(forResource: "billiard_hall_2k", withExtension: "hdr"),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
           let resource = try? await EnvironmentResource(equirectangular: image) {
            return resource
        }
        return try await warmInteriorIBL()
    }

    /// Tiny equirectangular gradient: warm glow above the horizon, dark wood
    /// tones below — the fallback ambient.
    @MainActor
    private static func warmInteriorIBL() async throws -> EnvironmentResource {
        let width = 64, height = 32
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * 4)

        for y in 0..<height {
            let v = Float(y) / Float(height - 1)          // 0 = top (zenith), 1 = bottom
            let color: SIMD3<Float>
            if v < 0.55 {
                // ceiling glow -> horizon warmth
                let t = v / 0.55
                color = mix(SIMD3(0.55, 0.47, 0.38), SIMD3(0.95, 0.72, 0.48), t: t)
            } else {
                // horizon -> dark floor
                let t = (v - 0.55) / 0.45
                color = mix(SIMD3(0.95, 0.72, 0.48), SIMD3(0.10, 0.07, 0.05), t: t)
            }
            for _ in 0..<width {
                pixels.append(UInt8(min(color.x, 1) * 255))
                pixels.append(UInt8(min(color.y, 1) * 255))
                pixels.append(UInt8(min(color.z, 1) * 255))
                pixels.append(255)
            }
        }

        let data = CFDataCreate(nil, pixels, pixels.count)!
        let provider = CGDataProvider(data: data)!
        let cgImage = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )!

        return try await EnvironmentResource(equirectangular: cgImage)
    }

    private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        a + (b - a) * max(0, min(1, t))
    }
}

extension Entity {
    func forEachDescendant(_ body: (Entity) -> Void) {
        for child in children {
            body(child)
            child.forEachDescendant(body)
        }
    }
}
