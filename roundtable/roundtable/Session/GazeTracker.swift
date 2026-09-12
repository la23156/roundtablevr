//
//  GazeTracker.swift
//  roundtable
//
//  Head-direction gaze proxy: polls the device anchor and classifies which
//  character seat the user is facing (visionOS exposes no raw eye gaze).
//

import ARKit
import Foundation
import QuartzCore
import simd

@MainActor
@Observable
final class GazeTracker {
    private let session = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    private var pollTask: Task<Void, Never>?

    /// Character seat directions to classify against: id -> head position.
    var characterHeads: [String: SIMD3<Float>] = [:]

    private(set) var headPosition = SIMD3<Float>(0, 1.2, 0)
    private(set) var headForward = SIMD3<Float>(0, 0, -1)
    /// Character the user is currently facing (within a ~15° half-angle cone,
    /// sustained; nil when facing nobody).
    private(set) var facedCharacterID: String?
    private var candidateID: String?
    private var candidateSince: Double = 0

    func start() async {
        do {
            try await session.run([worldTracking])
        } catch {
            print("GazeTracker: world tracking unavailable (\(error)); gaze features degrade gracefully")
            return
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .milliseconds(66))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        session.stop()
    }

    private func poll() {
        guard worldTracking.state == .running,
              let anchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { return }
        let m = anchor.originFromAnchorTransform
        headPosition = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        headForward = -SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)

        // Classify against character head directions.
        var best: (id: String, angle: Float)?
        for (id, head) in characterHeads {
            let dir = normalize(head - headPosition)
            let angle = acos(max(-1, min(1, dot(dir, normalize(headForward)))))
            if angle < 0.26, angle < (best?.angle ?? .infinity) {   // ~15°
                best = (id, angle)
            }
        }

        let now = CACurrentMediaTime()
        if let best {
            if candidateID != best.id {
                candidateID = best.id
                candidateSince = now
            } else if now - candidateSince > 0.3 {
                facedCharacterID = best.id
            }
        } else {
            candidateID = nil
            facedCharacterID = nil
        }
    }
}
