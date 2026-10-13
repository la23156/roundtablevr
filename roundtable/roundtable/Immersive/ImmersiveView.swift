//
//  ImmersiveView.swift
//  roundtable
//
//  The full-immersion classroom. Builds the scene for the frozen session
//  config, docks a small HUD attachment at the table edge, and manages the
//  window <-> space lifecycle.
//

import GroupActivities
import SwiftUI
import RealityKit

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow

    private static let hudAttachmentID = "sessionHUD"

    @State private var updateSubscription: EventSubscription?

    var body: some View {
        RealityView { content, attachments in
            guard let config = appModel.sessionConfig else { return }
            do {
                let handles = try await RoundtableScene.build(config: config)
                content.add(handles.root)
                RoundtableScene.setChalkTitle(config.topic.title, in: handles.root)

                if let hud = attachments.entity(for: Self.hudAttachmentID) {
                    // Low card at the user's table edge, tipped up toward the
                    // eyes. SharePlay replicas sit at a template guest seat,
                    // not the origin, so dock the HUD at THEIR table edge.
                    if let pose = appModel.groupCoordinator.systemCoordinator?
                        .localParticipantState.seat?.pose,
                       appModel.sessionController?.isGroupSession == true {
                        let seatPos = SIMD3<Float>(Float(pose.position.x), 0, Float(pose.position.z))
                        let toTable = SeatingLayout.tableCenter - seatPos
                        let dist = max(simd_length(SIMD3<Float>(toTable.x, 0, toTable.z)), 0.01)
                        let toward = SIMD3<Float>(toTable.x, 0, toTable.z) / dist
                        // Face the HUD back toward the seated user (+Z toward them).
                        let yaw = atan2(-toward.x, -toward.z)
                        hud.position = seatPos + toward * 1.03
                            + SIMD3<Float>(0, SeatingLayout.tableTopHeight + 0.16, 0)
                        hud.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                            * simd_quatf(angle: -0.45, axis: [1, 0, 0])
                    } else {
                        hud.position = [0, SeatingLayout.tableTopHeight + 0.16, -0.72]
                        hud.orientation = simd_quatf(angle: -0.45, axis: [1, 0, 0])
                    }
                    handles.root.addChild(hud)
                }
                if let subtitles = attachments.entity(for: "subtitles") {
                    // Floating caption above the far side of the table; scaled
                    // up so it's comfortably readable at ~3 m.
                    subtitles.position = [0, 1.75, -2.9]
                    subtitles.scale = SIMD3<Float>(repeating: 2.6)
                    handles.root.addChild(subtitles)
                }

                // Production path: build the cast and start the conversation
                // (spike launch args run their own reduced flows instead).
                let isSpike = ProcessInfo.processInfo.arguments.contains { $0 == "-visemeTest" || $0 == "-voiceTest" }
                if !isSpike, let controller = appModel.sessionController {
                    await controller.beginSession(handles: handles)
                    let start = CACurrentMediaTime()
                    var last = start
                    updateSubscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                        let now = CACurrentMediaTime()
                        controller.tick(time: now - start, dt: now - last)
                        last = now
                    }
                } else {
                    appModel.sessionController?.sceneHandles = handles
                }
            } catch {
                print("RoundtableScene build failed: \(error)")
            }

            // Phase 2 acceptance spike: `-visemeTest` puts one avatar right in
            // front of the user and flaps viseme_aa/jawOpen so a screenshot
            // can prove the blend-shape pipeline works end to end.
            if ProcessInfo.processInfo.arguments.contains("-visemeTest") {
                await runVisemeSpike(in: content)
            }

            // Phase 3 acceptance spike: `-voiceTest` generates one real
            // director turn, synthesizes it with the speaker's Fish Audio
            // voice, and plays it spatially with lip sync on a seated avatar.
            if ProcessInfo.processInfo.arguments.contains("-voiceTest") {
                await runVoiceSpike(in: content)
            }

            // Pose debug: `-sideSeat` spawns one seated avatar + chair
            // side-on in front of the camera so leg/chair alignment can be
            // verified from the fixed simulator viewpoint.
            if ProcessInfo.processInfo.arguments.contains("-sideSeat") {
                await runSideSeatSpike(in: content)
            }
        } attachments: {
            Attachment(id: Self.hudAttachmentID) {
                SessionHUDView(onLeave: leaveSession)
                    .environment(appModel)
            }
            Attachment(id: "subtitles") {
                SubtitleView()
                    .environment(appModel)
            }
        }
        .onAppear {
            appModel.immersiveSpaceState = .open
            appModel.phase = .inSession
            appModel.sessionController?.sessionDidBecomeActive()
        }
        // SharePlay: the group session ended (host left) — leave the space.
        .onChange(of: appModel.groupSessionEndedWhileImmersed) { _, ended in
            if ended { leaveSession() }
        }
        .onDisappear {
            appModel.immersiveSpaceState = .closed
            appModel.finishSession()
            // Bring the (dismissed) window back for the recap, including when
            // the user exited via the Digital Crown instead of the HUD button.
            openWindow(id: AppModel.mainWindowID)
        }
    }

    private func runVisemeSpike(in content: any RealityViewContentProtocol) async {
        do {
            let avatar = try await AvatarLoader.load(assetName: "Characters/brunette")
            avatar.root.position = [0, 0, -1.1]
            content.add(avatar.root)
            if let scene = appModel.sessionController?.sceneHandles,
               let ibl = scene.root.findEntity(named: "IBLSource") {
                avatar.root.forEachDescendantIncludingSelf { e in
                    if e.components.has(ModelComponent.self) {
                        e.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
                    }
                }
            }
            print("VISEME-SPIKE meshes with blendshapes: \(avatar.shapedMeshes.count)")
            print("VISEME-SPIKE canonical names: \(avatar.canonicalWeightNames.joined(separator: ", "))")
            let bounds = avatar.root.visualBounds(relativeTo: nil)
            print("VISEME-SPIKE bounds center=\(bounds.center) extents=\(bounds.extents)")
            avatar.root.forEachDescendantIncludingSelf { e in
                let model = (e as? ModelEntity)?.model != nil ? " [model]" : ""
                print("VISEME-SPIKE node: \(e.name)\(model) scale=\(e.scale)")
            }
            if let weightSet = avatar.shapedMeshes.first?.components[BlendShapeWeightsComponent.self]?.weightSet {
                for (i, set) in weightSet.enumerated() {
                    print("VISEME-SPIKE weightSet[\(i)] count=\(set.weights.count) rawNames[0..8]=\(set.weightNames.prefix(8))")
                }
            }

            // Static extreme pose: if ANY of these land on the bound mesh the
            // change is unmissable in a screenshot.
            avatar.setWeights([
                "viseme_aa": 1.0, "jawOpen": 1.0, "mouthOpen": 1.0,
                "eyesClosed": 1.0, "eyeBlinkLeft": 1.0, "eyeBlinkRight": 1.0,
                "browInnerUp": 1.0, "mouthSmile": 1.0,
            ])
        } catch {
            print("VISEME-SPIKE load failed: \(error)")
        }
    }

    private func runVoiceSpike(in content: any RealityViewContentProtocol) async {
        guard let config = appModel.sessionConfig else { return }
        do {
            // Seat the moderator's avatar at their real seat, facing the table.
            let moderator = config.moderator ?? config.cast[0]
            let seat = SeatingLayout.characterSeats(count: config.cast.count)[0]
            let avatar = try await AvatarLoader.load(assetName: "brunette")
            avatar.root.position = seat.position
            // Converted avatars face +Z natively; the seat yaw points -Z at
            // the table, so add a half turn.
            avatar.root.orientation = simd_quatf(angle: seat.yaw + .pi, axis: [0, 1, 0])
            content.add(avatar.root)
            if let scene = appModel.sessionController?.sceneHandles,
               let ibl = scene.root.findEntity(named: "IBLSource") {
                avatar.root.forEachDescendantIncludingSelf { e in
                    if e.components.has(ModelComponent.self) {
                        e.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
                    }
                }
            }

            let director = ConversationDirector(config: config)
            let lipSync = LipSyncDriver()

            print("VOICE-SPIKE generating turn…")
            let t0 = CACurrentMediaTime()
            guard let (turn, _) = try await director.generateNextTurn(
                directive: "Session start: \(moderator.name) opens with one warm line welcoming the table, then poses tonight's question."
            ) else { return }
            let tTurn = CACurrentMediaTime() - t0
            print("VOICE-SPIKE turn (\(String(format: "%.1f", tTurn))s): [\(turn.speaker)] \(turn.text)")

            let voice = CharacterRoster.spec(for: turn.speaker)?.voiceID ?? moderator.voiceID
            let (audioURL, duration) = try await DeepgramTTSClient().synthesize(text: turn.text, voiceID: voice)
            print("VOICE-SPIKE audio \(String(format: "%.1f", duration))s (total \(String(format: "%.1f", CACurrentMediaTime() - t0))s)")

            let mouth = CharacterAudio.mouthEntity(on: avatar.root)
            _ = try await CharacterAudio.play(url: audioURL, on: mouth)
            lipSync.speak(track: VisemeMapper.track(for: turn.text, duration: duration), avatar: avatar)
            print("VOICE-SPIKE playing with lip sync")

            Task {
                while lipSync.isSpeaking, !Task.isCancelled {
                    lipSync.update()
                    try? await Task.sleep(for: .milliseconds(16))
                }
                print("VOICE-SPIKE done")
            }
        } catch {
            print("VOICE-SPIKE failed: \(error)")
        }
    }

    private func runSideSeatSpike(in content: any RealityViewContentProtocol) async {
        do {
            // Clear the table so the profile view is unobstructed.
            appModel.sessionController?.sceneHandles?.root
                .findEntity(named: "HarknessTable")?.removeFromParent()

            let anchor = Entity()
            anchor.position = [0, 0, -1.6]
            // Rotate the whole seat 90° so the camera sees the side profile.
            anchor.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
            content.add(anchor)

            if let chairTemplate = await EnvAssets.model("SchoolChair_01") {
                let chair = EnvAssets.placed(chairTemplate, at: [0, 0, 0.05], yaw: -.pi / 2)
                anchor.addChild(chair)
            }
            let avatar = try await AvatarLoader.load(assetName: "brunette")
            let spec = CharacterRoster.all[0]
            let seat = Seat(position: anchor.position, yaw: .pi / 2)
            let character = CharacterEntity(spec: spec, seat: seat, anchor: anchor, avatar: avatar)
            character.lookTarget = nil
            if let scene = appModel.sessionController?.sceneHandles,
               let ibl = scene.root.findEntity(named: "IBLSource") {
                avatar.root.forEachDescendantIncludingSelf { e in
                    if e.components.has(ModelComponent.self) {
                        e.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
                    }
                }
            }
        } catch {
            print("sideSeat spike failed: \(error)")
        }
    }

    private func leaveSession() {
        Task { @MainActor in
            guard appModel.immersiveSpaceState == .open else { return }
            appModel.immersiveSpaceState = .inTransition
            await dismissImmersiveSpace()
        }
    }
}

/// Small diegetic control card docked at the user's edge of the table.
struct SessionHUDView: View {
    @Environment(AppModel.self) private var appModel
    var onLeave: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let controller = appModel.sessionController, controller.isHarkness {
                harknessStrip(controller: controller)
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hudTitle)
                        .font(.system(.headline, design: .serif))
                        .lineLimit(1)
                    Text(appModel.sessionController?.isTutorial == true
                         ? "Goal: turn every sticky note on the table green — without lecturing."
                         : appModel.sessionController?.isHarkness == true
                         ? "Guide with questions and silence — not answers."
                         : "Speak any time — or just look at someone.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let controller = appModel.sessionController, let doc = controller.document,
                   !controller.isReplicaSession {   // only the host flips pages
                    pageControls(controller: controller, doc: doc)
                }
                if appModel.groupCoordinator.sessionActive {
                    Label("\(appModel.groupCoordinator.participantCount)", systemImage: "person.2.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive, action: onLeave) {
                    Label("Leave", systemImage: "door.left.hand.open")
                        .labelStyle(.titleAndIcon)
                        .font(.callout)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassBackgroundEffect()
    }

    private var hudTitle: String {
        if appModel.sessionController?.isHarkness == true {
            return "HarknessAI — \(appModel.sessionConfig?.topic.title ?? "Training")"
        }
        return appModel.sessionConfig?.topic.title ?? "Roundtable"
    }

    /// HarknessAI training rows: score, tension meter, guideflow checklist,
    /// talk ratio, move feedback, and the coach's whisper.
    @ViewBuilder
    private func harknessStrip(controller: SessionController) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                // Running score.
                if let stats = controller.harknessStats {
                    Label("\(stats.score)", systemImage: "star.fill")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(stats.score >= 0 ? .yellow : .red)
                }

                // Silence Tension Meter (appears only during a stall).
                if let tension = controller.tensionProgress {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.slash")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        ProgressView(value: tension)
                            .progressViewStyle(.linear)
                            .tint(tension >= 1 ? .green : .orange)
                            .frame(width: 130)
                        Text("hold the silence")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Guideflow tracker: one dot per realization node; the one
                // the class is closing in on pulses amber.
                if let setup = appModel.sessionConfig?.mode.harknessSetup,
                   let stats = controller.harknessStats {
                    HStack(spacing: 5) {
                        ForEach(1...setup.realizationNodes.count, id: \.self) { i in
                            Image(systemName: stats.nodesCovered.contains(i)
                                  ? "circle.fill"
                                  : controller.closingInOn == i ? "circle.circle.fill" : "circle.dotted")
                                .font(.caption)
                                .foregroundStyle(stats.nodesCovered.contains(i) ? .yellow
                                                 : controller.closingInOn == i ? .orange : .secondary)
                        }
                    }
                    if let closing = controller.closingInOn {
                        Text("closing in on №\(closing)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }

                    // Live teacher talk-time share (target: under ~15%).
                    let ratio = Int(stats.teacherTalkRatio * 100)
                    Text("you: \(ratio)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(stats.teacherTalkRatio > 0.15 ? .red : .green)
                }

                // Move feedback flash.
                if let flash = controller.harknessFlash {
                    Text(flash.text)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(flash.positive ? .green : .red)
                        .lineLimit(1)
                        .transition(.opacity)
                        .id(flash.id)
                }
                Spacer(minLength: 0)
            }

            // The coach's whisper: what a good facilitator might do right now.
            if let hint = controller.coachHint {
                Label(hint, systemImage: "lightbulb.fill")
                    .font(.caption2.italic())
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controller.harknessFlash)
        .animation(.easeInOut(duration: 0.25), value: controller.tensionProgress == nil)
        .animation(.easeInOut(duration: 0.25), value: controller.coachHint)
        .animation(.easeInOut(duration: 0.25), value: controller.closingInOn)
    }

    /// "◀ Page N/M ▶" — flips the page on the presentation board.
    private func pageControls(controller: SessionController, doc: DiscussionDocument) -> some View {
        HStack(spacing: 8) {
            Button {
                controller.changePage(delta: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(doc.currentPageIndex == 0)

            Text("Page \(doc.currentPageIndex + 1)/\(doc.pageCount)")
                .font(.callout.monospacedDigit())
                .frame(minWidth: 74)

            Button {
                controller.changePage(delta: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(doc.currentPageIndex >= doc.pageCount - 1)
        }
    }
}
