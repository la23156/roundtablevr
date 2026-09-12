//
//  CompanionSessionView.swift
//  roundtable-ios
//
//  Live view of the shared session: subtitle ticker, running transcript,
//  the presentation board's current page (document sessions), and the
//  interjection mic button.
//

import SwiftUI

struct CompanionSessionView: View {
    @Environment(CompanionModel.self) private var model

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if model.hasDocument {
                                pageSection
                            }
                            transcriptSection
                        }
                        .padding(18)
                    }
                    .onChange(of: model.transcript.count) {
                        if let last = model.transcript.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                subtitleTicker
                micBar
            }
            .navigationTitle(model.topicTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Label("\(model.participantCount)", systemImage: "person.2.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Presentation page

    private var pageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("On the board", systemImage: "doc.richtext")
                    .font(.headline)
                Spacer()
                if model.pageCount > 0 {
                    Text("Page \(model.currentPageIndex + 1)/\(model.pageCount)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let image = model.pageImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
            } else {
                ProgressView("Receiving the deck…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            }
        }
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("The discussion", systemImage: "bubble.left.and.bubble.right")
                .font(.headline)
            if model.transcript.isEmpty {
                Text("The table is settling in…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.transcript) { line in
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.speaker)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(line.speaker == "You" ? Color.accentColor : .secondary)
                    Text(line.text)
                        .font(.system(.callout, design: .serif))
                }
                .id(line.id)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Subtitle ticker

    private var subtitleTicker: some View {
        Group {
            if let subtitle = model.subtitle {
                VStack(spacing: 3) {
                    Text(subtitle.speaker)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                    Text(subtitle.text)
                        .font(.system(.callout, design: .serif))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.85))
                .foregroundStyle(.white)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.subtitle?.text)
    }

    // MARK: - Mic

    private var micBar: some View {
        HStack(spacing: 14) {
            Button {
                model.toggleMic()
            } label: {
                Label(model.micLive ? "Mic live — tap to mute" : "Tap to speak to the table",
                      systemImage: model.micLive ? "mic.fill" : "mic")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.micLive ? .red : .accentColor)
        }
        .padding(14)
        .background(.bar)
    }
}
