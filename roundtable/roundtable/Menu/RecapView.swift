//
//  RecapView.swift
//  roundtable
//
//  Post-session recap: insight gems collected, transcript.
//

import SwiftUI

struct RecapView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let recap = appModel.lastRecap

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The table adjourns.")
                        .font(.system(size: 36, weight: .bold, design: .serif))
                    if let recap {
                        Text("\(recap.topicTitle) · \(max(recap.durationMinutes, 1)) min")
                            .font(.system(.title3, design: .serif))
                            .foregroundStyle(.secondary)
                    }
                }

                if let recap, !recap.insights.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Insights collected — \(recap.insights.count)")
                            .font(.system(.title2, design: .serif).weight(.semibold))
                        ForEach(recap.insights) { insight in
                            HStack(spacing: 10) {
                                Image(systemName: "diamond.fill")
                                    .foregroundStyle(insight.sparkedByUser ? .yellow : .green)
                                VStack(alignment: .leading) {
                                    Text(insight.title)
                                        .font(.system(.headline, design: .serif))
                                    Text(insight.sparkedByUser ? "Sparked by you" : insight.speakerName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    Text("No insights made it to the rack this time — interject more!")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.secondary)
                }

                if let recap, !recap.transcript.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(recap.transcript) { line in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.speakerName)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                    Text(line.text + (line.wasInterrupted ? " —" : ""))
                                        .font(.callout)
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("Transcript")
                            .font(.system(.title3, design: .serif).weight(.semibold))
                    }
                }

                Button {
                    appModel.returnToMenu()
                } label: {
                    Label("Back to the menu", systemImage: "arrow.uturn.backward")
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(32)
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(.regularMaterial)
    }
}

#Preview(windowStyle: .automatic) {
    RecapView()
        .environment(AppModel())
}
