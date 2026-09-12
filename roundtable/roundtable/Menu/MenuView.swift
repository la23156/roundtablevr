//
//  MenuView.swift
//  roundtable
//
//  Pre-session menu: topic deck, cast picker, settings, enter button.
//

import SwiftUI
import UniformTypeIdentifiers

struct MenuView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

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

    private var documentIsSelected: Bool {
        selectedTopicID == "pdf" && pendingDocument != nil
    }

    private var selectedTopic: TopicCard? {
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
        selectedTopic != nil && castIsValid && appModel.phase == .menu
            && appModel.immersiveSpaceState == .closed
            && (!documentIsSelected || documentPhase == .ready)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                topicSection
                castSection
                settingsSection
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
            //   -pdfTest   loads the bundled SamplePitch.pdf, summarizes it,
            //              then auto-enters in document mode.
            //   -autoEnter enters immediately with the default topic.
            Task { await appModel.characterStore.refresh() }
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-cardTest") {
                openWindow(id: AppModel.castTableWindowID)
            }
            if args.contains("-pdfTest") {
                runPDFTest()
            } else if args.contains("-autoEnter") {
                enterRoundtable()
            }
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
        selectedTopicID = "pdf"
        documentPhase = .summarizing
        print("PDF: loaded \"\(doc.title)\" — \(doc.pageCount) pages")

        Task {
            do {
                let (summary, entities) = try await OpenAIClient().summarizeDocument(text: doc.fullText)
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

    private func enterRoundtable() {
        // Phase guard: the window flips back to MenuView when the session
        // starts, which re-fires onAppear — never start a second session.
        guard appModel.phase == .menu, appModel.sessionController == nil,
              let topic = selectedTopic else { return }
        let cast = appModel.characterStore.all.filter { appModel.selectedCastIDs.contains($0.id) }
        let document = documentIsSelected ? pendingDocument : nil
        document?.currentPageIndex = 0
        let config = SessionConfig(topic: topic, cast: cast, settings: settings,
                                   document: document?.info)

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
