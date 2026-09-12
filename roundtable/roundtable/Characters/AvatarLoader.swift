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

    /// Loads an avatar USDZ bundled directly in the app (AvatarAssets/<name>.usdz).
    ///
    /// Avatars deliberately bypass RealityKitContent: realitytool's .reality
    /// compilation does not preserve working blend-shape animation, while a
    /// directly loaded USDZ does.
    @MainActor
    static func load(assetName: String) async throws -> LoadedAvatar {
        let name = assetName.components(separatedBy: "/").last ?? assetName
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz") else {
            throw LoadError.missingResource(name)
        }
        let entity = try await Entity(contentsOf: url)
        return LoadedAvatar(root: entity)
    }
}

extension Entity {
    func forEachDescendantIncludingSelf(_ body: (Entity) -> Void) {
        body(self)
        forEachDescendant(body)
    }
}
