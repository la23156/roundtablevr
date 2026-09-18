//
//  AvatarLoader.swift
//  roundtable
//
//  Loads converted avatar USDZs from RealityKitContent and exposes their
//  blend-shape meshes for lip sync / expressions.
//
//  Note on names: the Blender conversion suffixes duplicate blend-shape names
//  per mesh (viseme_aa, viseme_aa2, viseme_aa3, …), so all lookups here match
//  on prefix: `weight(named: "viseme_aa")` drives every mesh's variant.
//

import Foundation
import RealityKit
import RealityKitContent
import UIKit

/// A loaded avatar plus fast paths to its animatable parts.
@MainActor
final class LoadedAvatar {
    let root: Entity
    /// Entities carrying BlendShapeWeightsComponent (head, teeth, eyes, …).
    let shapedMeshes: [ModelEntity]
    /// Canonical blend-shape name (suffix stripped) -> [(mesh index, weight index)].
    private let weightIndex: [String: [(mesh: Int, index: Int)]]

    init(root: Entity) {
        self.root = root

        var meshes: [ModelEntity] = []
        var index: [String: [(mesh: Int, index: Int)]] = [:]
        root.forEachDescendantIncludingSelf { entity in
            guard let model = entity as? ModelEntity,
                  let component = model.components[BlendShapeWeightsComponent.self] else { return }
            let meshIdx = meshes.count
            meshes.append(model)
            for (setIdx, set) in component.weightSet.enumerated() {
                guard setIdx == 0 else { continue } // one weight set per mesh in our assets
                for (i, rawName) in set.weightNames.enumerated() {
                    index[Self.canonical(rawName), default: []].append((meshIdx, i))
                }
            }
        }
        self.shapedMeshes = meshes
        self.weightIndex = index
    }

    /// Strips the trailing digits Blender appends to deduplicate names, and
    /// any USD namespace prefix.
    static func canonical(_ raw: String) -> String {
        var name = raw
        if let colon = name.lastIndex(of: ":") {
            name = String(name[name.index(after: colon)...])
        }
        while let last = name.last, last.isNumber {
            name.removeLast()
        }
        return name
    }

    var canonicalWeightNames: [String] { Array(weightIndex.keys).sorted() }

    /// Recolors this avatar's clothing (HarknessAI: duplicate bodies get the
    /// student's tint so twins are tellable apart, and shirt color matches
    /// the student's color everywhere else in the UI). Matches entities whose
    /// names look like garments; skips skin/face/hair. Returns the number of
    /// entities tinted (0 = this rig bakes clothes into the body mesh).
    @discardableResult
    func tintClothing(_ color: UIColor) -> Int {
        // RealityKit collapses the whole rig into ONE entity ("Armature")
        // whose ModelComponent holds every mesh as a submodel; garment names
        // survive as MeshResource.Model ids, and each model's parts index
        // into the shared materials array. Only TOPS are recolored (pants
        // and shoes keep their textures), and the recolor is a flat matte
        // cotton — texture dropped, no emissive — so it reads as a plain
        // colored shirt, not a glow suit.
        let tops = ["outfit_top", "shirt", "hoodie", "sweater", "casualsuit", "onesie", "dress"]
        let skip = ["bottom", "shoe", "footwear", "body", "head", "face", "eye",
                    "teeth", "tooth", "hair", "skin", "merged"]
        var tinted = 0
        var seenModelIDs: [String] = []
        root.forEachDescendantIncludingSelf { entity in
            guard var component = entity.components[ModelComponent.self] else { return }
            var garmentIndices = Set<Int>()
            for model in component.mesh.contents.models {
                let name = model.id.lowercased()
                seenModelIDs.append(model.id)
                guard tops.contains(where: { name.contains($0) }),
                      !skip.contains(where: { name.contains($0) }) else { continue }
                for part in model.parts {
                    garmentIndices.insert(part.materialIndex)
                }
            }
            guard !garmentIndices.isEmpty else { return }
            var materials = component.materials
            for index in garmentIndices where index < materials.count {
                guard var pbm = materials[index] as? PhysicallyBasedMaterial else { continue }
                pbm.baseColor = .init(tint: color)   // flat matte fabric, no texture
                pbm.roughness = .init(floatLiteral: 0.85)
                pbm.metallic = .init(floatLiteral: 0)
                materials[index] = pbm
                tinted += 1
            }
            component.materials = materials
            entity.components.set(component)
        }
        if tinted == 0 {
            print("AVATAR tintClothing: no top-garment match among submodels \(seenModelIDs)")
        }
        return tinted
    }

    /// Applies `updates` (canonical name -> weight) to all meshes in one pass.
    func setWeights(_ updates: [String: Float]) {
        guard !updates.isEmpty else { return }
        var perMesh: [Int: [(Int, Float)]] = [:]
        for (name, value) in updates {
            for slot in weightIndex[name] ?? [] {
                perMesh[slot.mesh, default: []].append((slot.index, value))
            }
        }
        for (meshIdx, changes) in perMesh {
            let model = shapedMeshes[meshIdx]
            guard var component = model.components[BlendShapeWeightsComponent.self] else { continue }
            var weights = component.weightSet[0].weights
            for (i, value) in changes where i < weights.count {
                weights[i] = value
            }
            component.weightSet[0].weights = weights
            model.components.set(component)
        }
    }

}

enum AvatarLoader {
    enum LoadError: Error { case missingResource(String) }

    /// First-load cache so a cast can reuse a body (HarknessAI seats 8
    /// students on 5 rigs). Later loads clone the cached entity — clones
    /// carry their own component instances (skeleton poses, blend-shape
    /// weights), so two copies animate independently.
    @MainActor private static var cache: [String: Entity] = [:]

    /// Loads an avatar USDZ bundled directly in the app (AvatarAssets/<name>.usdz).
    ///
    /// Avatars deliberately bypass RealityKitContent: realitytool's .reality
    /// compilation does not preserve working blend-shape animation, while a
    /// directly loaded USDZ does.
    @MainActor
    static func load(assetName: String) async throws -> LoadedAvatar {
        let name = assetName.components(separatedBy: "/").last ?? assetName
        if let cached = cache[name] {
            return LoadedAvatar(root: cached.clone(recursive: true))
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz") else {
            throw LoadError.missingResource(name)
        }
        let entity = try await Entity(contentsOf: url)
        cache[name] = entity
        return LoadedAvatar(root: entity.clone(recursive: true))
    }
}

extension Entity {
    func forEachDescendantIncludingSelf(_ body: (Entity) -> Void) {
        body(self)
        forEachDescendant(body)
    }
}
