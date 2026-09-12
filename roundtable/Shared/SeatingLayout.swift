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

    // MARK: - SharePlay human guests

    /// Maximum remote humans that get a seat/easel around the table.
    static let maxHumanGuests = 4

    /// Seats for remote HUMAN participants (Spatial Personas / iPhone guest
    /// easels), interleaved with the AI cast on the same ellipse.
    ///
    /// The AI cast occupies the arc opposite the host (see characterSeats);
    /// guests fill the gap boundaries of that arc: slots 0 and 1 flank the
    /// host just inside the clearance zone edges (left/right of the host),
    /// slots 2 and 3 bisect the first/last AI seat gaps. All slots are >= 1 m
    /// apart from each other and from the host seat at the origin — Personas
    /// need personal space; AI avatars may sit closer.
    ///
    /// The SharePlay spatial template uses these SAME coordinates (template
    /// origin == group immersive space origin, WWDC24 10201), so a Persona
    /// lands exactly where the scene renders its empty chair. The slot
    /// geometry is fixed (computed for the maximum cast of 5) so the template
    /// is identical on every device regardless of tonight's cast size.
    static func humanPersonaSeats() -> [Seat] {
        let a = tableSemiX + seatSetback
        let b = tableSemiZ + seatSetback
        let arcStart = userAngle + userClearance
        let arcLength = 2 * .pi - 2 * userClearance
        let n: Float = 5

        // Arc parameters t in [0,1]: 0/1 are the clearance edges beside the
        // host; 1/n and (n-1)/n bisect the outermost AI seat gaps.
        let params: [Float] = [0, 1, 1 / n, (n - 1) / n]

        return params.prefix(maxHumanGuests).map { t in
            let theta = arcStart + t * arcLength
            let position = tableCenter + SIMD3<Float>(a * cos(theta), 0, b * sin(theta))
            let toCenter = tableCenter - position
            let yaw = atan2(-toCenter.x, -toCenter.z)
            return Seat(position: position, yaw: yaw)
        }
    }

    /// Host seat in template/space coordinates (the space origin, facing the
    /// table center).
    static let hostSeatPosition = SIMD3<Float>(0, 0, 0)
}
