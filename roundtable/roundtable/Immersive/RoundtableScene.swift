//
//  RoundtableScene.swift
//  roundtable
//
//  Builds the antique classroom: textured room shell, Meshy-generated
//  Harkness table (procedural fallback), Poly Haven furniture, and the seat
//  anchors the cast hangs off. Everything degrades gracefully to gray-box
//  primitives if an asset fails to load.
//

import RealityKit
import SwiftUI
import UIKit

/// References into the built scene that the session logic needs.
@MainActor
struct RoundtableSceneHandles {
    let root: Entity
    /// Per cast-member anchor at their seat (floor level, facing the table).
    /// Avatars, placeholder bodies, and speech audio all hang off these.
    let characterAnchors: [String: Entity]
    /// Where insight gems land (near table edge, user's right).
    let gemRack: Entity
    let seats: [String: Seat]
}

enum RoundtableScene {

    static let roomW: Float = 9, roomD: Float = 7, roomH: Float = 3.6

    @MainActor
    static func build(config: SessionConfig) async throws -> RoundtableSceneHandles {
        let root = Entity()
        root.name = "RoundtableRoot"

        await buildRoomShell(into: root)
        await buildTable(into: root, topicTitle: config.topic.title)
        await buildFurniture(into: root)
        buildPresentationBoard(into: root, visible: config.document != nil)
        if config.document != nil, let chalk = root.findEntity(named: "ChalkTitle") {
            // Nudge the chalk title up so it clears the presentation board.
            chalk.position.y = 2.35
        }

        let chairTemplate = await EnvAssets.model("SchoolChair_01")

        var anchors: [String: Entity] = [:]
        var seatMap: [String: Seat] = [:]
        let seats = SeatingLayout.characterSeats(count: config.cast.count)
        for (spec, seat) in zip(config.cast, seats) {
            let anchor = buildCharacterSeat(spec: spec, seat: seat, chairTemplate: chairTemplate)
            anchors[spec.id] = anchor
            seatMap[spec.id] = seat
            root.addChild(anchor)
        }

        let gemRack = buildGemRack()
        root.addChild(gemRack)

        try await LightingRig.install(on: root)

        return RoundtableSceneHandles(root: root, characterAnchors: anchors, gemRack: gemRack, seats: seatMap)
    }

    // MARK: - Materials

    private static func wood(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, roughness: Float = 0.6) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: r, green: g, blue: b, alpha: 1))
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: 0.0)
        return m
    }

    private static var darkOak: PhysicallyBasedMaterial { wood(0.26, 0.17, 0.10, roughness: 0.45) }
    private static var mediumOak: PhysicallyBasedMaterial { wood(0.42, 0.28, 0.16) }

    // MARK: - Room shell

    @MainActor
    private static func buildRoomShell(into root: Entity) async {
        let wainscotH: Float = 1.1
        let c = SeatingLayout.tableCenter
        let shell = Entity()
        shell.name = "RoomShell"
        shell.position = SIMD3<Float>(c.x, 0, c.z)

        let floorMat = await EnvAssets.pbr("herringbone_parquet", tilesX: 5, tilesY: 4,
                                           fallbackTint: UIColor(red: 0.35, green: 0.24, blue: 0.15, alpha: 1))
        var wainscotMat = await EnvAssets.pbr("mocha_oak_veneer", tilesX: 6, tilesY: 1,
                                              fallbackTint: UIColor(red: 0.26, green: 0.17, blue: 0.10, alpha: 1))
        // The veneer photographs light; multiply it toward antique dark oak.
        wainscotMat.baseColor.tint = UIColor(red: 0.55, green: 0.38, blue: 0.24, alpha: 1)
        let plasterMat = await EnvAssets.pbr("clay_plaster", tilesX: 4, tilesY: 2,
                                             fallbackTint: UIColor(red: 0.82, green: 0.75, blue: 0.62, alpha: 1))
        var ceilingMat = plasterMat
        ceilingMat.textureCoordinateTransform = .init(scale: SIMD2<Float>(3, 3))

        func box(_ name: String, w: Float, h: Float, d: Float,
                 at p: SIMD3<Float>, material: PhysicallyBasedMaterial) {
            let e = ModelEntity(mesh: .generateBox(width: w, height: h, depth: d), materials: [material])
            e.name = name
            e.position = p
            shell.addChild(e)
        }

        box("Floor", w: roomW, h: 0.05, d: roomD, at: [0, -0.025, 0], material: floorMat)
        box("Ceiling", w: roomW, h: 0.05, d: roomD, at: [0, roomH + 0.025, 0], material: ceilingMat)

        let t: Float = 0.1
        let upperH = roomH - wainscotH
        for (name, z) in [("WallN", -roomD / 2), ("WallS", roomD / 2)] {
            box("\(name)_wainscot", w: roomW, h: wainscotH, d: t, at: [0, wainscotH / 2, z], material: wainscotMat)
            box("\(name)_upper", w: roomW, h: upperH, d: t, at: [0, wainscotH + upperH / 2, z], material: plasterMat)
        }
        for (name, x) in [("WallE", roomW / 2), ("WallW", -roomW / 2)] {
            box("\(name)_wainscot", w: t, h: wainscotH, d: roomD, at: [x, wainscotH / 2, 0], material: wainscotMat)
            box("\(name)_upper", w: t, h: upperH, d: roomD, at: [x, wainscotH + upperH / 2, 0], material: plasterMat)
        }
        // Chair rail + crown molding strips (front walls only for cost).
        for z in [-roomD / 2 + t, roomD / 2 - t] {
            box("ChairRail", w: roomW, h: 0.07, d: 0.04, at: [0, wainscotH + 0.035, z], material: darkOak)
            box("Crown", w: roomW, h: 0.09, d: 0.06, at: [0, roomH - 0.045, z], material: darkOak)
        }
        for x in [-roomW / 2 + t, roomW / 2 - t] {
            box("ChairRailE", w: 0.04, h: 0.07, d: roomD, at: [x, wainscotH + 0.035, 0], material: darkOak)
            box("CrownE", w: 0.06, h: 0.09, d: roomD, at: [x, roomH - 0.045, 0], material: darkOak)
        }

        root.addChild(shell)
    }

    // MARK: - Table

    @MainActor
    private static func buildTable(into root: Entity, topicTitle: String) async {
        let table = Entity()
        table.name = "HarknessTable"
        table.position = SeatingLayout.tableCenter

        if let hero = await EnvAssets.model("harkness_table") {
            // Scale the generated table to the seating footprint and center it.
            EnvAssets.ground(hero)
            let bounds = hero.visualBounds(relativeTo: nil)
            let scaleX = (SeatingLayout.tableSemiX * 2) / max(bounds.extents.x, 0.01)
            let scaleZ = (SeatingLayout.tableSemiZ * 2) / max(bounds.extents.z, 0.01)
            let scaleY = SeatingLayout.tableTopHeight / max(bounds.extents.y, 0.01)
            hero.scale *= SIMD3<Float>(scaleX, scaleY, scaleZ)
            EnvAssets.ground(hero)
            table.addChild(hero)
        } else {
            // Procedural fallback: oval top + pedestal legs.
            let top = ModelEntity(
                mesh: .generateCylinder(height: SeatingLayout.tableTopThickness, radius: 1),
                materials: [darkOak]
            )
            top.name = "TableTop"
            top.scale = [SeatingLayout.tableSemiX, 1, SeatingLayout.tableSemiZ]
            top.position = [0, SeatingLayout.tableTopHeight - SeatingLayout.tableTopThickness / 2, 0]
            table.addChild(top)
            for x in [-1.0 as Float, 1.0] {
                let leg = ModelEntity(mesh: .generateCylinder(height: 0.69, radius: 0.22), materials: [darkOak])
                leg.position = [x, 0.345, 0]
                table.addChild(leg)
            }
        }

        // Soft contact-shadow disc (classic grounding trick).
        var shadow = UnlitMaterial(color: UIColor(white: 0, alpha: 0.35))
        shadow.blending = .transparent(opacity: 0.35)
        let disc = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: 1), materials: [shadow])
        disc.name = "TableShadow"
        disc.scale = [SeatingLayout.tableSemiX + 0.15, 1, SeatingLayout.tableSemiZ + 0.15]
        disc.position = [0, 0.002, 0]
        table.addChild(disc)

        // Books + oil lamp as table dressing at the center.
        if let books = await EnvAssets.model("book_encyclopedia_set_01") {
            table.addChild(EnvAssets.placed(books, at: [0.35, SeatingLayout.tableTopHeight, 0], yaw: 0.4))
        }
        if let lamp = await EnvAssets.model("vintage_oil_lamp") {
            table.addChild(EnvAssets.placed(lamp, at: [-0.4, SeatingLayout.tableTopHeight, 0.1], yaw: -0.2))
        }

        root.addChild(table)
    }

    // MARK: - Furniture around the room

    @MainActor
    private static func buildFurniture(into root: Entity) async {
        let c = SeatingLayout.tableCenter

        // Bookshelves along the east/west walls.
        if let shelfTemplate = await EnvAssets.model("wooden_bookshelf_worn") {
            for (x, yaw) in [(-roomW / 2 + 0.4, Float.pi / 2), (roomW / 2 - 0.4, -Float.pi / 2)] {
                for z in [-1.9 as Float, 0, 1.9] {
                    let shelf = shelfTemplate.clone(recursive: true)
                    root.addChild(EnvAssets.placed(shelf, at: [c.x + x, 0, c.z + z], yaw: yaw))
                }
            }
        }

        // Standing chalkboard tucked into the far corner at an angle.
        if let board = await EnvAssets.model("standing_chalkboard_01") {
            root.addChild(EnvAssets.placed(board, at: [c.x - roomW / 2 + 1.0, 0, c.z - roomD / 2 + 1.0], yaw: 0.7))
        }

        root.addChild(chalkTitle(SeatingLayout.tableCenter))
    }

    /// The session topic handwritten in "chalk" on the far wall.
    @MainActor
    private static func chalkTitle(_ c: SIMD3<Float>) -> Entity {
        let mesh = MeshResource.generateText(
            "",
            extrusionDepth: 0.004,
            font: .init(descriptor: .init(name: "Bradley Hand", size: 1), size: 0.22),
            containerFrame: CGRect(x: 0, y: 0, width: 4, height: 1.2),
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        var chalk = UnlitMaterial(color: UIColor(white: 0.92, alpha: 1))
        chalk.blending = .transparent(opacity: 0.92)
        let entity = ModelEntity(mesh: mesh, materials: [chalk])
        entity.name = "ChalkTitle"
        entity.position = [c.x - 2, 2.1, c.z - roomD / 2 + 0.12]
        return entity
    }

    // MARK: - Presentation board ("discuss a PDF" mode)

    /// Base size of the white presentation surface; the surface is scaled down
    /// on one axis to letterbox the displayed page's aspect ratio.
    private static let boardSurfaceW: Float = 2.2
    private static let boardSurfaceH: Float = 1.55

    /// Framed board mounted on the far (north) wall, centered above the table.
    /// Hidden unless the session is discussing a document.
    @MainActor
    private static func buildPresentationBoard(into root: Entity, visible: Bool) {
        let c = SeatingLayout.tableCenter
        let wallZ = c.z - roomD / 2

        let board = Entity()
        board.name = "PresentationBoard"
        board.position = [c.x, 1.8, wallZ + 0.16]

        let frame = ModelEntity(
            mesh: .generateBox(width: boardSurfaceW + 0.14, height: boardSurfaceH + 0.14, depth: 0.06),
            materials: [darkOak]
        )
        frame.name = "BoardFrame"
        board.addChild(frame)

        let blank = UnlitMaterial(color: UIColor(white: 0.97, alpha: 1))
        let surface = ModelEntity(
            mesh: .generatePlane(width: boardSurfaceW, height: boardSurfaceH),
            materials: [blank]
        )
        surface.name = "PresentationSurface"
        surface.position = [0, 0, 0.035]
        board.addChild(surface)

        board.isEnabled = visible
        root.addChild(board)
    }

    /// Swaps the rendered page onto the board, letterboxing to preserve the
    /// image aspect (scales the surface within its 2.2 x 1.55 m frame).
    @MainActor
    static func setBoardImage(_ cgImage: CGImage, in root: Entity) async {
        guard let surface = root.findEntity(named: "PresentationSurface") as? ModelEntity else { return }
        guard let texture = try? await TextureResource(
            image: cgImage,
            options: .init(semantic: .color)
        ) else {
            print("PresentationBoard: texture creation failed")
            return
        }
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        surface.model?.materials = [material]

        let aspect = Float(cgImage.width) / Float(max(cgImage.height, 1))
        var w = boardSurfaceW
        var h = w / aspect
        if h > boardSurfaceH {
            h = boardSurfaceH
            w = h * aspect
        }
        surface.scale = [w / boardSurfaceW, h / boardSurfaceH, 1]
    }

    /// Regenerates the chalk title text (called once the topic is known).
    @MainActor
    static func setChalkTitle(_ text: String, in root: Entity) {
        guard let entity = root.findEntity(named: "ChalkTitle") as? ModelEntity else { return }
        entity.model?.mesh = try! MeshResource.generateText(
            text,
            extrusionDepth: 0.004,
            font: .init(descriptor: .init(name: "Bradley Hand", size: 1), size: 0.22),
            containerFrame: CGRect(x: 0, y: 0, width: 4, height: 1.2),
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
    }

    // MARK: - Character seats

    /// Anchor entity at the seat (floor level, -Z facing the table center)
    /// containing a chair and, until an avatar replaces it, a tinted
    /// placeholder body.
    private static func buildCharacterSeat(spec: CharacterSpec, seat: Seat, chairTemplate: Entity?) -> Entity {
        let anchor = Entity()
        anchor.name = "char_\(spec.id)"
        anchor.position = seat.position
        anchor.orientation = simd_quatf(angle: seat.yaw, axis: [0, 1, 0])

        if let chairTemplate {
            let chair = chairTemplate.clone(recursive: true)
            // Measured from the USDZ geometry: SchoolChair_01's backrest sits
            // at model -Z, so yaw π puts it at anchor +Z — behind the seated
            // character, chair facing the table center.
            let placed = EnvAssets.placed(chair, at: [0, 0, 0.05], yaw: .pi)
            placed.name = "Chair"
            anchor.addChild(placed)
        } else {
            let chair = Entity()
            chair.name = "Chair"
            let pan = ModelEntity(mesh: .generateBox(width: 0.46, height: 0.05, depth: 0.46), materials: [mediumOak])
            pan.position = [0, 0.44, 0]
            chair.addChild(pan)
            let back = ModelEntity(mesh: .generateBox(width: 0.46, height: 0.55, depth: 0.05), materials: [mediumOak])
            back.position = [0, 0.72, 0.23]
            chair.addChild(back)
            anchor.addChild(chair)
        }

        // Placeholder occupant (replaced by the avatar in-session).
        let tint = UIColor(spec.tint)
        var bodyMat = PhysicallyBasedMaterial()
        bodyMat.baseColor = .init(tint: tint)
        bodyMat.roughness = .init(floatLiteral: 0.8)

        let placeholder = Entity()
        placeholder.name = "Placeholder"
        let torso = ModelEntity(mesh: .generateCylinder(height: 0.55, radius: 0.17), materials: [bodyMat])
        torso.position = [0, 0.75, 0]
        placeholder.addChild(torso)
        let head = ModelEntity(mesh: .generateSphere(radius: 0.11), materials: [bodyMat])
        head.name = "Head"
        head.position = [0, SeatingLayout.seatedEyeHeight, 0]
        placeholder.addChild(head)
        anchor.addChild(placeholder)

        // Look-target + hover affordance covering the character's upper body.
        anchor.components.set(CollisionComponent(shapes: [
            .generateCapsule(height: 1.0, radius: 0.3).offsetBy(translation: [0, 0.85, 0])
        ]))
        anchor.components.set(InputTargetComponent())
        anchor.components.set(HoverEffectComponent())

        return anchor
    }

    // MARK: - SharePlay guest seats

    /// Empty chairs at the human guest slots (rendered only while a group
    /// session is active). Spatial Personas land on these seats via the
    /// template; iPhone guests get a ParticipantCardEntity easel on top.
    @MainActor
    static func installGuestSeats(in root: Entity, seats: [Seat]) async {
        guard root.findEntity(named: "GuestSeats") == nil else { return }
        let container = Entity()
        container.name = "GuestSeats"
        let chairTemplate = await EnvAssets.model("SchoolChair_01")
        for (i, seat) in seats.enumerated() {
            let anchor = Entity()
            anchor.name = "guestSeat_\(i)"
            anchor.position = seat.position
            anchor.orientation = simd_quatf(angle: seat.yaw, axis: [0, 1, 0])
            if let chairTemplate {
                let chair = EnvAssets.placed(chairTemplate.clone(recursive: true), at: [0, 0, 0.05], yaw: .pi)
                chair.name = "Chair"
                anchor.addChild(chair)
            } else {
                let pan = ModelEntity(mesh: .generateBox(width: 0.46, height: 0.05, depth: 0.46), materials: [mediumOak])
                pan.position = [0, 0.44, 0]
                anchor.addChild(pan)
                let back = ModelEntity(mesh: .generateBox(width: 0.46, height: 0.55, depth: 0.05), materials: [mediumOak])
                back.position = [0, 0.72, 0.23]
                anchor.addChild(back)
            }
            container.addChild(anchor)
        }
        root.addChild(container)
        print("SESSION guest seating installed (\(seats.count) slots)")
    }

    // MARK: - Gem rack

    private static func buildGemRack() -> Entity {
        let rack = ModelEntity(mesh: .generateBox(width: 0.5, height: 0.03, depth: 0.12), materials: [mediumOak])
        rack.name = "GemRack"
        rack.position = SIMD3<Float>(0.55, SeatingLayout.tableTopHeight + 0.015,
                                     SeatingLayout.tableCenter.z + SeatingLayout.tableSemiZ - 0.25)
        return rack
    }
}
