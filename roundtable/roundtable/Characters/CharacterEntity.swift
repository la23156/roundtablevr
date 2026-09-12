//
//  CharacterEntity.swift
//  roundtable
//
//  A cast member in the scene: loaded avatar seated at its anchor, procedural
//  seated pose + idle motion (until real animation clips land), head look-at,
//  blinking, and a mouth audio emitter.
//

import Foundation
import QuartzCore
import RealityKit

@MainActor
final class CharacterEntity {
    let spec: CharacterSpec
    let seat: Seat
    let anchor: Entity
    let avatar: LoadedAvatar
    let mouth: Entity

    /// Every skinned model in the avatar (some rigs load as face + body with
    /// separate skeleton instances — all must be posed in lockstep).
    private var skinnedModels: [ModelEntity] = []
    private var jointNames: [String] = []
    private var jointIndex: [String: Int] = [:]
    private var restPose: [Transform] = []

    /// Current head look target in world space (nil = rest).
    var lookTarget: SIMD3<Float>?
    private var lookYaw: Float = 0      // smoothed, radians, relative to rest
    private var lookPitch: Float = 0

    private var nextBlink: Double = 1.5
    private var blinkPhase: Double = -1

    var headWorldPosition: SIMD3<Float> {
        anchor.convert(position: [0, SeatingLayout.seatedEyeHeight, 0], to: nil)
    }

    init(spec: CharacterSpec, seat: Seat, anchor: Entity, avatar: LoadedAvatar) {
        self.spec = spec
        self.seat = seat
        self.anchor = anchor
        self.avatar = avatar

        // Avatars face +Z natively; the anchor's -Z faces the table.
        avatar.root.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        anchor.addChild(avatar.root)
        self.mouth = CharacterAudio.mouthEntity(on: anchor)

        indexSkeleton()
        applySeatedPose()
    }

    // MARK: - Skeleton access

    private func indexSkeleton() {
        avatar.root.forEachDescendantIncludingSelf { entity in
            guard let model = entity as? ModelEntity,
                  let skeleton = model.model?.mesh.contents.skeletons.first(where: { _ in true }) else { return }
            skinnedModels.append(model)
            guard jointNames.isEmpty else { return }   // index from the first; assume shared layout
            jointNames = skeleton.joints.map(\.name)
            for (i, name) in jointNames.enumerated() {
                // Names are full paths like "Armature/Hips/Spine"; index by leaf too.
                jointIndex[name] = i
                if let leaf = name.split(separator: "/").last {
                    jointIndex[String(leaf)] = i
                }
            }
            if let poses = model.components[SkeletalPosesComponent.self],
               let pose = poses.poses.default {
                restPose = Array(pose.jointTransforms)
            }
        }
        if skinnedModels.count > 1 {
            print("CharacterEntity \(spec.id): \(skinnedModels.count) skinned models (posing all)")
        }
    }

    /// Accumulated rest-pose rotation of the joint's PARENT chain, in avatar
    /// (model) space. Used to convert avatar-space deltas into joint-local ones.
    private func restParentWorldRotation(of index: Int) -> simd_quatf {
        let path = jointNames[index]
        var rotation = simd_quatf(angle: 0, axis: [0, 1, 0])
        let components = path.split(separator: "/")
        guard components.count > 1 else { return rotation }
        for depth in 1..<components.count {
            let prefix = components[0..<depth].joined(separator: "/")
            if let j = jointIndex[prefix] {
                rotation = rotation * restPose[j].rotation
            }
        }
        return rotation
    }

    /// Rest-pose joint position in avatar space (full ancestor accumulation).
    private func restWorldPosition(of index: Int) -> SIMD3<Float> {
        let path = jointNames[index]
        var world = Transform.identity
        let components = path.split(separator: "/")
        for depth in 1...components.count {
            let prefix = components[0..<depth].joined(separator: "/")
            if let j = jointIndex[prefix] {
                world = Transform(matrix: world.matrix * restPose[j].matrix)
            }
        }
        return world.translation
    }

    /// Rotates `joint` so the bone toward `tipJoint` points along `direction`
    /// (avatar space). Rig-agnostic: axis and angle come from the rig's own
    /// rest geometry, so it works regardless of joint-local conventions.
    private func aimJoint(_ joint: String, tip tipJoint: String, toward direction: SIMD3<Float>) -> simd_quatf? {
        guard let j = jointIndex[joint], let t = jointIndex[tipJoint] else { return nil }
        let boneDir = normalize(restWorldPosition(of: t) - restWorldPosition(of: j))
        let target = normalize(direction)
        let d = max(-1, min(1, dot(boneDir, target)))
        if d > 0.9995 { return simd_quatf(angle: 0, axis: [0, 1, 0]) }
        let axis = d < -0.9995 ? SIMD3<Float>(0, 0, 1) : normalize(cross(boneDir, target))
        return simd_quatf(angle: acos(d), axis: axis)
    }

    /// Applies avatar-space rotation deltas (correct regardless of each rig's
    /// joint-local axis conventions, as long as ancestors stay near rest).
    private func setJointsAvatarSpace(_ updates: [String: simd_quatf]) {
        var locals: [String: simd_quatf] = [:]
        for (name, delta) in updates {
            guard let i = jointIndex[name] else { continue }
            let parentWorld = restParentWorldRotation(of: i)
            locals[name] = parentWorld.inverse * delta * parentWorld * restPose[i].rotation
        }
        setJointsAbsoluteLocal(locals)
    }

    /// Sets joint-local rotations directly (already composed with rest).
    private func setJointsAbsoluteLocal(_ rotations: [String: simd_quatf]) {
        forEachSkinnedPose { transforms in
            for (name, rotation) in rotations {
                guard let i = jointIndex[name], i < transforms.count else { continue }
                var t = transforms[i]
                t.rotation = rotation
                transforms[i] = t
            }
        }
    }

    private func setJoints(_ updates: [String: simd_quatf], translations: [String: SIMD3<Float>] = [:]) {
        forEachSkinnedPose { transforms in
            for (name, rotation) in updates {
                guard let i = jointIndex[name], i < transforms.count else { continue }
                var t = restPose[i]
                t.rotation = restPose[i].rotation * rotation
                if let extra = translations[name] { t.translation += extra }
                transforms[i] = t
            }
            for (name, extra) in translations where updates[name] == nil {
                guard let i = jointIndex[name], i < transforms.count else { continue }
                var t = transforms[i]
                t.translation = restPose[i].translation + extra
                transforms[i] = t
            }
        }
    }

    /// Applies a mutation to every skinned model's default pose.
    private func forEachSkinnedPose(_ mutate: (inout JointTransforms) -> Void) {
        guard !restPose.isEmpty else { return }
        for model in skinnedModels {
            guard var poses = model.components[SkeletalPosesComponent.self],
                  var pose = poses.poses.default,
                  pose.jointTransforms.count == restPose.count else { continue }
            var transforms = pose.jointTransforms
            mutate(&transforms)
            pose.jointTransforms = transforms
            poses.poses.default = pose
            model.components.set(poses)
        }
    }

    // MARK: - Seated pose

    /// Static procedural sit: thighs forward 90°, knees back 90°, pelvis
    /// dropped to chair height, slight spine lean and arm relaxation.
    ///
    /// IMPORTANT frame note: the Hips joint's local translation lives in the
    /// skeleton root's frame, which is Z-UP (up = +Z) with -Y toward the
    /// table. The drop is computed per rig from its actual standing hip
    /// height so different-proportioned avatars all land on the chair pan.
    func applySeatedPose() {
        let deg: (Float) -> Float = { $0 * .pi / 180 }
        let standingHipHeight = jointIndex["Hips"].map { restWorldPosition(of: $0).z } ?? 0.95
        let seatedPelvisHeight: Float = 0.52   // chair pan (~0.45) + thigh thickness
        let drop: SIMD3<Float> = [0, 0.08, -(standingHipHeight - seatedPelvisHeight)]
        var rotations: [String: simd_quatf] = [:]
        // Hip flexion: +X local rotation brings the thighs FORWARD (toward
        // the character's facing); the previous negative sign folded the legs
        // backward under the chair.
        for side in ["Left", "Right"] {
            rotations["\(side)UpLeg"] = simd_quatf(angle: deg(88), axis: [1, 0, 0])
            rotations["\(side)Leg"] = simd_quatf(angle: deg(-85), axis: [1, 0, 0])
        }
        rotations["Spine"] = simd_quatf(angle: deg(4), axis: [1, 0, 0])
        rotations["Spine1"] = simd_quatf(angle: deg(3), axis: [1, 0, 0])
        setJoints(rotations, translations: ["Hips": drop])

        // Relax A/T-pose arms: aim each upper arm mostly down with a little
        // outward drift, using the rig's own rest geometry. NOTE: the USD
        // skeleton rest frame is Z-UP (Blender's frame survives in UsdSkel
        // even though the meshes render Y-up), so "down" here is -Z.
        var armAims: [String: simd_quatf] = [:]
        for (arm, fore, outward) in [("LeftArm", "LeftForeArm", Float(1)), ("RightArm", "RightForeArm", Float(-1))] {
            if let aim = aimJoint(arm, tip: fore, toward: [0.30 * outward, 0, -0.95]) {
                armAims[arm] = aim
            }
        }
        setJointsAvatarSpace(armAims)
    }

    var debugJointNames: [String] { jointNames }

    // MARK: - Per-frame idle

    /// Breathing sway, blinks, and smoothed head look-at. `time` is a shared
    /// scene clock; `dt` the frame delta.
    func updateIdle(time: Double, dt: Double) {
        // --- head look-at (yaw/pitch relative to facing direction)
        var targetYaw: Float = 0
        var targetPitch: Float = 0
        if let target = lookTarget {
            let local = anchor.convert(position: target, from: nil)
            // Anchor -Z faces the table; avatar head at seated eye height.
            let d = local - SIMD3<Float>(0, SeatingLayout.seatedEyeHeight, 0)
            targetYaw = atan2(-d.x, -d.z)
            let horizontal = max(sqrt(d.x * d.x + d.z * d.z), 0.001)
            targetPitch = atan2(d.y, horizontal)
            targetYaw = max(-1.0, min(1.0, targetYaw))      // ±57°
            targetPitch = max(-0.45, min(0.45, targetPitch))
        }
        let alpha = Float(1 - exp(-dt / 0.25))
        lookYaw += (targetYaw - lookYaw) * alpha
        lookPitch += (targetPitch - lookPitch) * alpha

        // --- breathing
        let breath = Float(sin(time * 2 * .pi * 0.22)) * 0.02

        // Head joint: yaw about Y, pitch about X (negative pitch looks up in
        // joint space after the mirroring below — tuned empirically).
        let headRot = simd_quatf(angle: lookYaw, axis: [0, 1, 0])
            * simd_quatf(angle: -lookPitch, axis: [1, 0, 0])
        setJoints([
            "Head": headRot,
            "Neck": simd_quatf(angle: lookYaw * 0.3, axis: [0, 1, 0]),
            "Spine2": simd_quatf(angle: breath, axis: [1, 0, 0]),
        ])

        // --- blinking
        if blinkPhase < 0, time > nextBlink {
            blinkPhase = time
        }
        if blinkPhase >= 0 {
            let p = (time - blinkPhase) / 0.18   // 180 ms blink
            let w = Float(p < 0.5 ? p * 2 : max(0, 2 - p * 2))
            avatar.setWeights(["eyeBlinkLeft": w, "eyeBlinkRight": w, "eyesClosed": w * 0.6])
            if p >= 1 {
                blinkPhase = -1
                nextBlink = time + Double.random(in: 2.2...5.5)
            }
        }
    }
}
