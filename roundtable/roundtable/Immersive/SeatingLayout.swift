//
//  SeatingLayout.swift
//  roundtable
//
//  Geometry for the Harkness table and everyone around it.
//
//  Coordinate convention (full immersive space): origin on the floor at the
//  user's feet, -Z forward. The user's seat is the near wide side of the oval;
//  the table center sits straight ahead so the user is already "at the table"
//  when the space opens.
//

import simd

struct Seat {
    let position: SIMD3<Float>   // floor point of the chair
    let yaw: Float               // rotation about Y so -Z faces the table center
}

enum SeatingLayout {
    // Tabletop ellipse semi-axes (X is the long axis) and height.
    static let tableSemiX: Float = 1.9
    static let tableSemiZ: Float = 1.2
    static let tableTopHeight: Float = 0.72
    static let tableTopThickness: Float = 0.06

    /// How far a chair sits back from the table edge.
    static let seatSetback: Float = 0.55

    /// Nominal eye height of a seated adult; used to place character heads
    /// and (Phase 6) calibrate the scene to the user's real seated height.
    static let seatedEyeHeight: Float = 1.18

    /// Table center is straight ahead so the user's edge point lands at the origin.
    static let tableCenter = SIMD3<Float>(0, 0, -(tableSemiZ + seatSetback))

    /// The user's seat parameter angle on the ellipse (near wide side).
    private static let userAngle: Float = .pi / 2
    /// Characters are kept out of this half-angle around the user's seat so
    /// nobody sits in the user's lap — everyone lands across the table.
    private static let userClearance: Float = 80 * .pi / 180

    /// Evenly spaced character seats on the ellipse arc opposite the user.
    static func characterSeats(count: Int) -> [Seat] {
        guard count > 0 else { return [] }
        let a = tableSemiX + seatSetback
        let b = tableSemiZ + seatSetback
        let arcStart = userAngle + userClearance
        let arcLength = 2 * .pi - 2 * userClearance

        return (0..<count).map { i in
            // Inset spacing: seats at (i+0.5)/N keep clear of the arc edges.
            let t = (Float(i) + 0.5) / Float(count)
            let theta = arcStart + t * arcLength
            let position = tableCenter + SIMD3<Float>(a * cos(theta), 0, b * sin(theta))
            let toCenter = tableCenter - position
            // yaw such that the seat's -Z axis points at the table center
            let yaw = atan2(-toCenter.x, -toCenter.z)
            return Seat(position: position, yaw: yaw)
        }
    }

    /// Direction from the user (origin) to each character seat's head, used by
    /// GazeTracker to decide which character the user is facing.
    static func headPosition(of seat: Seat) -> SIMD3<Float> {
        SIMD3<Float>(seat.position.x, seatedEyeHeight, seat.position.z)
    }
}
