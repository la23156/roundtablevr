//
//  MenuView.swift
//  roundtable
//
//  Pre-session menu: topic deck, cast picker, settings, enter button.
//

import GroupActivities
import SwiftUI
import UniformTypeIdentifiers

struct MenuView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    /// SharePlay eligibility (true while in a FaceTime call / nearby group).
    @StateObject private var groupStateObserver = GroupStateObserver()

    @State private var selectedTopicID: String? = TopicDeck.presets.first?.id
    @State private var customTopicText = ""
    @State private var settings = SessionSettings()
    @State private var enterError: String?

    // "Discuss a PDF" mode.
    enum DocumentPhase: Equatable {
        case idle, summarizing, ready
        case failed(String)
    }
    @State private var showingPDFImporter = false
    @State private var pendingDocument: DiscussionDocument?
    @State private var documentPhase: DocumentPhase = .idle

    // HarknessAI teacher-training mode.
    @State private var harknessNodes: [String] = ["", "", "", "", ""]
    @State private var nodeSuggestionPrompt = ""
    @State private var suggestingNodes = false
    @State private var nodeSuggestionError: String?

    private var harknessSelected: Bool { selectedTopicID == "harkness" }

    private var validHarknessNodes: [String] {
        harknessNodes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var documentIsSelected: Bool {
        (selectedTopicID == "pdf" || harknessSelected) && pendingDocument != nil
    }

    private var selectedTopic: TopicCard? {
        if harknessSelected {
            guard let doc = pendingDocument else { return nil }
            return .custom(doc.title)
        }
        if documentIsSelected, let doc = pendingDocument {
            return .custom("\(doc.title) — investment discussion")
        }
        if selectedTopicID == "custom" {
            let trimmed = customTopicText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .custom(trimmed)
        }
        return TopicDeck.presets.first { $0.id == selectedTopicID }
    }

    private var castIsValid: Bool {
        (3...5).contains(appModel.selectedCastIDs.count) && appModel.selectedCastIDs.contains("elowen")
    }

    private var canEnter: Bool {
        guard appModel.phase == .menu, appModel.immersiveSpaceState == .closed else { return false }
        if harknessSelected {
            // Training runs need the artifact + 3-5 realization nodes; the
            // class roster is generated, so the cast picker doesn't apply.
            return pendingDocument != nil && documentPhase == .ready
                && (3...5).contains(validHarknessNodes.count)
        }
        return selectedTopic != nil && castIsValid
            && (!documentIsSelected || documentPhase == .ready)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                topicSection
                if harknessSelected {
                    harknessSection
                } else {
                    castSection
                }
                settingsSection
                shareSection
                enterSection
            }
            .padding(32)
        }
        .frame(minWidth: 760, minHeight: 640)
        .background(.regularMaterial)
        .fileImporter(isPresented: $showingPDFImporter, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result {
                loadDocument(from: url, securityScoped: true)
            }
        }
        .onAppear {
            // Debug hooks so automated simulator runs can reach the immersive
            // scene without UI interaction:
            //   -pdfTest        loads the bundled SamplePitch.pdf, summarizes
            //                   it, then auto-enters in document mode.
            //   -autoEnter      enters immediately with the default topic.
            //   -rtMessageTest  round-trips every SharePlay message + prints
            //                   the seating template math, then idles.
            Task { await appModel.characterStore.refresh() }
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-cardTest") {
                openWindow(id: AppModel.castTableWindowID)
            }
            if args.contains("-rtMessageTest") {
                RTMessageSelfTest.run()
            }
            if args.contains("-tutorialTest") {
                enterTutorial()
            } else if args.contains("-harknessTest") {
                runHarknessTest()
            } else if args.contains("-pdfTest") {
                runPDFTest()
            } else if args.contains("-autoEnter") {
                enterRoundtable()
            }
        }
        // SharePlay replica: the host entered the shared space and we have
        // the snapshot — follow them in.
        .onChange(of: appModel.replicaStartTick) {
            startReplicaIfReady()
        }
    }

    // MARK: - SharePlay

    private var shareSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bring Friends")
                .font(.system(.title2, design: .serif).weight(.semibold))
            if appModel.groupCoordinator.sessionActive {
                HStack(spacing: 12) {
                    Image(systemName: "shareplay")
                        .foregroundStyle(.green)
                    Text(appModel.groupCoordinator.isHost
                         ? "Sharing the Roundtable — \(appModel.groupCoordinator.participantCount) at the table"
                         : "Joined a shared Roundtable — \(appModel.groupCoordinator.participantCount) at the table")
                        .font(.callout)
                    if !appModel.groupCoordinator.isHost {
                        Text("waiting for the host to enter…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if groupStateObserver.isEligibleForGroupSession {
                HStack(spacing: 12) {
                    Button {
                        Task {
                            await appModel.groupCoordinator.activate(
                                topicTitle: selectedTopic?.title ?? "Roundtable")
                        }
                    } label: {
                        Label("Share the Roundtable", systemImage: "shareplay")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    Text("Friends on FaceTime join at the table — Vision Pro as Personas, iPhone on a table card.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Start a FaceTime call to share the Roundtable (SharePlay).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Replica flow: needs (1) an active non-host group session, (2) the
    /// host's snapshot, (3) the group immersion style saying "open".
    private func startReplicaIfReady() {
        guard appModel.phase == .menu, appModel.sessionController == nil,
              appModel.immersiveSpaceState == .closed,
              appModel.groupCoordinator.sessionActive,
              !appModel.groupCoordinator.isHost,
              appModel.groupWantsImmersive,
              let snapshot = appModel.pendingSnapshot else { return }
        guard appModel.beginReplicaSession(snapshot: snapshot) else { return }
        appModel.immersiveSpaceState = .inTransition
        Task {
            switch await openImmersiveSpace(id: AppModel.immersiveSpaceID) {
            case .opened:
                dismissWindow(id: AppModel.mainWindowID)
                dismissWindow(id: AppModel.castTableWindowID)
            default:
                appModel.immersiveSpaceState = .closed
                appModel.sessionController = nil
                appModel.phase = .menu
            }
        }
    }

    /// `-harknessTest`: HarknessAI training run against the bundled sample
    /// deck with canned realization nodes (simulator verification).
    private func runHarknessTest() {
        guard appModel.phase == .menu, appModel.sessionController == nil,
              pendingDocument == nil else { return }
        guard let url = Bundle.main.url(forResource: "SamplePitch", withExtension: "pdf") else {
            print("HARKNESS-TEST: SamplePitch.pdf missing from bundle")
            return
        }
        selectedTopicID = "harkness"
        harknessNodes = [
            "The company's real moat is regulatory, not technical",
            "The revenue projections assume a customer that doesn't exist yet",
            "The team slide is stronger than the product slide",
            "", "",
        ]
        print("HARKNESS-TEST: loading bundled sample text")
        loadDocument(from: url, securityScoped: false)
        // loadDocument's summarize completion auto-enters for -pdfTest only;
        // mirror that here once the briefing is ready.
        Task {
            while documentPhase != .ready {
                if case .failed = documentPhase { return }
                try? await Task.sleep(for: .milliseconds(300))
            }
            enterRoundtable()
        }
    }

    /// `-pdfTest`: full document flow against the bundled sample deck.
    private func runPDFTest() {
        guard appModel.phase == .menu, appModel.sessionController == nil,
              pendingDocument == nil else { return }
        guard let url = Bundle.main.url(forResource: "SamplePitch", withExtension: "pdf") else {
            print("PDF-TEST: SamplePitch.pdf missing from bundle")
            return
        }
        print("PDF-TEST: loading bundled sample deck")
        loadDocument(from: url, securityScoped: false)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Roundtable")
                .font(.system(size: 44, weight: .bold, design: .serif))
            Text("Take a seat. Pick a question worth arguing about.")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(.secondary)
        }
    }

    private var topicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tonight's Question")
                .font(.system(.title2, design: .serif).weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    harknessTopicCard
                    pdfTopicCard
                    ForEach(TopicDeck.presets) { card in
                        TopicCardView(card: card, isSelected: selectedTopicID == card.id)
                            .onTapGesture { selectedTopicID = card.id }
                    }
                    customTopicCard
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var harknessTopicCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🎓").font(.system(size: 30))
            Text("HarknessAI")
                .font(.system(.headline, design: .serif))
            Text("Teacher training: guide a simulated class of 8 students through a Harkness discussion using only questions and silence.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 230, height: 150, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(harknessSelected ? Color.green.opacity(0.18) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(harknessSelected ? Color.green : .clear, lineWidth: 2)
        )
        .onTapGesture { selectedTopicID = "harkness" }
        .hoverEffect()
    }

    /// HarknessAI setup: the artifact (PDF), the guideflow (realization
    /// nodes), and the generated class.
    private var harknessSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Training Setup")
                .font(.system(.title2, design: .serif).weight(.semibold))

            // 0. The 90-second tutorial — no PDF needed.
            HStack(spacing: 12) {
                Image(systemName: "graduationcap.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New here? Play the 90-second tutorial")
                        .font(.headline)
                    Text("A scripted class on the fall of Rome walks you through every mechanic: the crib cards, the pulse, a deflection trap, and one glorious silence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    enterTutorial()
                } label: {
                    Label("Start tutorial", systemImage: "play.fill")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(appModel.phase != .menu || appModel.immersiveSpaceState != .closed)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.green.opacity(0.08)))

            // 1. The artifact.
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pendingDocument?.title ?? "Upload the artifact")
                        .font(.headline)
                    switch documentPhase {
                    case .idle:
                        Text("The reading, historical document, or case study your class will discuss.")
                            .font(.caption).foregroundStyle(.secondary)
                    case .summarizing:
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Reading the text…").font(.caption).foregroundStyle(.secondary)
                        }
                    case .ready:
                        Text("\(pendingDocument?.pageCount ?? 0) pages · the class has done the reading")
                            .font(.caption).foregroundStyle(.secondary)
                    case .failed(let message):
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                }
                Spacer()
                Button(pendingDocument == nil ? "Choose PDF…" : "Change PDF…") {
                    showingPDFImporter = true
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))

            // 2. The guideflow.
            VStack(alignment: .leading, spacing: 8) {
                Text("Realization Nodes")
                    .font(.headline)
                Text("3–5 understandings the class should reach on their own. You'll see them as orbs above the table — they turn gold when the students get there without you telling them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Auto-suggest from the artifact (optional steer prompt).
                HStack(spacing: 10) {
                    TextField("Optional steer — e.g. \"focus on the narrator's blind spots\"",
                              text: $nodeSuggestionPrompt)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                    Button {
                        suggestNodes()
                    } label: {
                        if suggestingNodes {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Reading…")
                            }
                        } else {
                            Label("Suggest nodes", systemImage: "wand.and.stars")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(pendingDocument == nil || suggestingNodes)
                }
                if pendingDocument == nil {
                    Text("Upload the artifact first and I can draft the nodes from it.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let nodeSuggestionError {
                    Text(nodeSuggestionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                ForEach(0..<5, id: \.self) { i in
                    TextField(nodePlaceholder(i), text: $harknessNodes[i])
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))

            // 3. The goal & the class.
            VStack(alignment: .leading, spacing: 6) {
                Text("How to Play")
                    .font(.headline)
                Text("YOUR GOAL: get the class to reach every realization above ON THEIR OWN — you may only steer with questions, your gaze, and silence. Your crib notes lie on the table in front of you (only you'd recognize them): a note pulses amber as the discussion closes in on it, and when a student lands it, it glows green, gets crossed out, and you score +100.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Eight students take their seats — a Monopolizer who fills every silence, a Tangent Weaver, a silent Ghost who knows the answers, one confidently incorrect voice, and an Echo. Hold silences until a student cracks (+40), deflect \"is that right?\" back to the table (+30), tether tangents to the text (+10), and keep your talk-time under 15%. Answering for them costs points.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
        }
    }

    /// Drafts realization nodes from the uploaded artifact (fast model),
    /// steered by the optional prompt. Results land in the editable fields.
    private func suggestNodes() {
        guard let doc = pendingDocument, !suggestingNodes else { return }
        suggestingNodes = true
        nodeSuggestionError = nil
        let guidance = nodeSuggestionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let nodes = try await OpenAIClient()
                    .suggestRealizationNodes(documentText: doc.fullText, guidance: guidance)
                guard pendingDocument === doc else { return }
                for i in 0..<5 {
                    harknessNodes[i] = i < nodes.count ? nodes[i] : ""
                }
                print("HARKNESS suggested nodes: \(nodes.joined(separator: " | "))")
            } catch {
                nodeSuggestionError = "Couldn't draft nodes: \(error.localizedDescription)"
                print("HARKNESS node suggestion failed: \(error)")
            }
            suggestingNodes = false
        }
    }

    private func nodePlaceholder(_ i: Int) -> String {
        [
            "e.g. The narrator can't be trusted — the story contradicts him",
            "e.g. The setting mirrors the protagonist's state of mind",
            "e.g. The 'villain' is following the same logic as the hero",
            "Optional fourth realization…",
            "Optional fifth realization…",
        ][i]
    }

    private var pdfTopicCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📄").font(.system(size: 30))
            Text(pendingDocument?.title ?? "Discuss a PDF")
                .font(.system(.headline, design: .serif))
                .lineLimit(2)
            switch documentPhase {
            case .idle:
                Text("Pick an investment deck; the table examines it page by page.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .summarizing:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Reading the deck…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .ready:
                Text("\(pendingDocument?.pageCount ?? 0) pages · briefing ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Button(pendingDocument == nil ? "Choose PDF…" : "Change PDF…") {
                showingPDFImporter = true
            }
            .font(.caption)
        }
        .padding(16)
        .frame(width: 230, height: 150, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(selectedTopicID == "pdf" ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(selectedTopicID == "pdf" ? Color.accentColor : .clear, lineWidth: 2)
        )
        .onTapGesture {
            if pendingDocument == nil {
                showingPDFImporter = true
            } else {
                selectedTopicID = "pdf"
            }
        }
        .hoverEffect()
    }

    // MARK: - Document loading

    private func loadDocument(from url: URL, securityScoped: Bool) {
        let scoped = securityScoped ? url.startAccessingSecurityScopedResource() : false
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let doc = DiscussionDocument(url: url) else {
            documentPhase = .failed("Couldn't read that PDF.")
            return
        }
        pendingDocument = doc
        if !harknessSelected { selectedTopicID = "pdf" }
        documentPhase = .summarizing
        print("PDF: loaded \"\(doc.title)\" — \(doc.pageCount) pages")

        Task {
            do {
                let (summary, entities) = try await OpenAIClient()
                    .summarizeDocument(text: doc.fullText, forTraining: harknessSelected)
                // The user may have picked a different PDF while we summarized.
                guard pendingDocument === doc else { return }
                doc.docSummary = summary
                doc.entities = entities
                documentPhase = .ready
                print("PDF: briefing ready — entities: \(entities.joined(separator: ", "))")
                print("PDF: summary: \(summary.prefix(200))")
                if ProcessInfo.processInfo.arguments.contains("-pdfTest") {
                    enterRoundtable()
                }
            } catch {
                guard pendingDocument === doc else { return }
                documentPhase = .failed("Summarize failed: \(error.localizedDescription)")
                print("PDF: summarize failed: \(error)")
            }
        }
    }

    private var customTopicCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("✍️").font(.system(size: 30))
            Text("Write your own")
                .font(.system(.headline, design: .serif))
            TextField("What should we discuss?", text: $customTopicText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2, reservesSpace: true)
                .font(.callout)
                .onChange(of: customTopicText) { _, newValue in
                    if !newValue.isEmpty { selectedTopicID = "custom" }
                }
        }
        .padding(16)
        .frame(width: 230, height: 150, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(selectedTopicID == "custom" ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(selectedTopicID == "custom" ? Color.accentColor : .clear, lineWidth: 2)
        )
        .onTapGesture { selectedTopicID = "custom" }
    }

    private var castSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("The Table")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                Spacer()
                Button {
                    openWindow(id: AppModel.castTableWindowID)
                } label: {
                    Label("Deal the cards", systemImage: "rectangle.portrait.on.rectangle.portrait.angled")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.bordered)
                Text("choose 3–5 · Prof. Hart moderates")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 5), spacing: 14) {
                ForEach(appModel.characterStore.all) { spec in
                    CastTileView(spec: spec, isSelected: appModel.selectedCastIDs.contains(spec.id))
                        .onTapGesture { toggleCast(spec) }
                }
            }
        }
    }

    private func toggleCast(_ spec: CharacterSpec) {
        if spec.isModerator { return } // moderator always seated
        if appModel.selectedCastIDs.contains(spec.id) {
            appModel.selectedCastIDs.remove(spec.id)
        } else {
            appModel.selectedCastIDs.insert(spec.id)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session")
                .font(.system(.title2, design: .serif).weight(.semibold))
            HStack(spacing: 24) {
                Picker("Length", selection: $settings.sessionMinutes) {
                    Text("10 min").tag(10)
                    Text("15 min").tag(15)
                    Text("20 min").tag(20)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)

                Toggle("Fresh facts from the web", isOn: $settings.freshFactsEnabled)
                    .toggleStyle(.switch)
                    .frame(maxWidth: 300)

                Toggle("Subtitles", isOn: $settings.subtitlesEnabled)
                    .toggleStyle(.switch)
                    .frame(maxWidth: 180)
            }
        }
    }

    private var enterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                enterRoundtable()
            } label: {
                Label("Enter the Roundtable", systemImage: "chair.lounge.fill")
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canEnter)

            if let enterError {
                Text(enterError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    /// The scripted 90-second HarknessAI tutorial (no PDF, canned beats).
    private func enterTutorial() {
        guard appModel.phase == .menu, appModel.sessionController == nil else { return }
        let config = SessionConfig(topic: .custom(TutorialScript.topicTitle),
                                   cast: HarknessStudents.tutorialCast,
                                   settings: settings,
                                   document: nil,
                                   mode: .harkness(TutorialScript.setup))
        appModel.beginSession(config: config, document: nil)
        appModel.immersiveSpaceState = .inTransition
        enterError = nil
        Task {
            switch await openImmersiveSpace(id: AppModel.immersiveSpaceID) {
            case .opened:
                dismissWindow(id: AppModel.mainWindowID)
                dismissWindow(id: AppModel.castTableWindowID)
            default:
                appModel.immersiveSpaceState = .closed
                appModel.sessionController = nil
                appModel.phase = .menu
            }
        }
    }

    private func enterRoundtable() {
        // Phase guard: the window flips back to MenuView when the session
        // starts, which re-fires onAppear — never start a second session.
        guard appModel.phase == .menu, appModel.sessionController == nil,
              let topic = selectedTopic else { return }
        let config: SessionConfig
        let document: DiscussionDocument?
        if harknessSelected {
            // HarknessAI: the class roster is generated; the teacher (user)
            // moderates by definition.
            document = pendingDocument
            document?.currentPageIndex = 0
            let setup = HarknessSetup(realizationNodes: validHarknessNodes)
            config = SessionConfig(topic: topic, cast: HarknessStudents.roster(),
                                   settings: settings, document: document?.info,
                                   mode: .harkness(setup))
        } else {
            let cast = appModel.characterStore.all.filter { appModel.selectedCastIDs.contains($0.id) }
            document = documentIsSelected ? pendingDocument : nil
            document?.currentPageIndex = 0
            config = SessionConfig(topic: topic, cast: cast, settings: settings,
                                   document: document?.info)
        }

        appModel.beginSession(config: config, document: document)
        appModel.immersiveSpaceState = .inTransition
        enterError = nil

        Task {
            switch await openImmersiveSpace(id: AppModel.immersiveSpaceID) {
            case .opened:
                dismissWindow(id: AppModel.mainWindowID)
                dismissWindow(id: AppModel.castTableWindowID)
            case .userCancelled:
                appModel.immersiveSpaceState = .closed
                appModel.sessionController = nil
                appModel.phase = .menu
            case .error:
                fallthrough
            @unknown default:
                appModel.immersiveSpaceState = .closed
                appModel.sessionController = nil
                appModel.phase = .menu
                enterError = "Couldn't open the immersive space. Try again."
            }
        }
    }
}

private struct TopicCardView: View {
    let card: TopicCard
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.emoji).font(.system(size: 30))
            Text(card.title)
                .font(.system(.headline, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            Text(card.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 230, height: 150, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .hoverEffect()
    }
}

private struct CastTileView: View {
    let spec: CharacterSpec
    let isSelected: Bool

    private var initials: String {
        spec.name.split(separator: " ").compactMap(\.first).suffix(2).map(String.init).joined()
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(spec.tint.opacity(isSelected ? 0.85 : 0.3))
                    .frame(width: 64, height: 64)
                Text(initials)
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundStyle(.white)
            }
            Text(spec.name)
                .font(.system(.subheadline, design: .serif).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(spec.archetype)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(spec.bio)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(3)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? spec.tint.opacity(0.15) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isSelected ? spec.tint : .clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            if spec.isModerator {
                Text("MODERATOR")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(spec.tint.opacity(0.8)))
                    .foregroundStyle(.white)
                    .padding(6)
            }
        }
        .hoverEffect()
    }
}

#Preview(windowStyle: .automatic) {
    MenuView()
        .environment(AppModel())
}
