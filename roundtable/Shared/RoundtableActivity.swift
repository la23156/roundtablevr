//
//  RoundtableActivity.swift
//  roundtable (shared: visionOS + iOS companion)
//
//  The SharePlay group activity. On visionOS the session initiator hosts the
//  AI pipeline; everyone else (Vision Pro Personas, iPhone companions) is a
//  replica that re-synthesizes and plays the same turns locally.
//

import Foundation
import GroupActivities
import Spatial

struct RoundtableActivity: GroupActivity, Sendable {
    static let activityIdentifier = "com.spmhresearch.roundtable.session"

    /// Shown in the system share sheet / FaceTime banner.
    var topicTitle: String

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.type = .generic
        metadata.title = "Roundtable: \(topicTitle)"
        metadata.subtitle = "Join the table and argue with the cast."
        // The host runs the whole AI pipeline; there is no host migration.
        metadata.lifetimePolicy = .endsWhenInitiatorLeaves
        return metadata
    }
}

#if os(visionOS)

/// Seat roles: the initiator gets the host seat at the space origin.
enum RoundtableSeatRole: String, SpatialTemplateRole {
    case host
}

/// Custom Persona seating: host at the origin facing the table, up to four
/// guest seats interleaved with the AI cast on the ellipse. Template origin ==
/// group immersive space origin, so SeatingLayout coordinates are used as-is.
struct RoundtableTemplate: SpatialTemplate {
    var configuration: SpatialTemplateConfiguration {
        SpatialTemplateConfiguration(defaultInitiatorRole: RoundtableSeatRole.host)
    }

    var elements: [any SpatialTemplateElement] {
        let center = SeatingLayout.tableCenter
        let lookingAtTable = SpatialTemplateElementDirection.lookingAt(
            .app.offsetBy(x: Double(center.x), z: Double(center.z)))

        var seats: [any SpatialTemplateElement] = [
            .seat(position: .app.offsetBy(x: 0, z: 0),
                  direction: lookingAtTable,
                  role: RoundtableSeatRole.host)
        ]
        for seat in SeatingLayout.humanPersonaSeats() {
            seats.append(.seat(
                position: .app.offsetBy(x: Double(seat.position.x), z: Double(seat.position.z)),
                direction: lookingAtTable))
        }
        return seats
    }
}

#endif
