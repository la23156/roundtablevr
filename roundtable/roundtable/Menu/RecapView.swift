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
                    Text(recap?.harknessDebrief == nil ? "The table adjourns." : "Class dismissed.")
                        .font(.system(size: 36, weight: .bold, design: .serif))
                    if let recap {
                        Text("\(recap.topicTitle) · \(max(recap.durationMinutes, 1)) min")
                            .font(.system(.title3, design: .serif))
                            .foregroundStyle(.secondary)
                    }
                }

                if let debrief = recap?.harknessDebrief {
                    HarknessDebriefView(debrief: debrief)
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

/// HarknessAI post-game analytics: talk-time ratio, intervention quality,
/// table equity, silence discipline, and guideflow coverage.
private struct HarknessDebriefView: View {
    let debrief: HarknessDebrief

    private var stats: HarknessStats { debrief.stats }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Teaching Debrief")
                .font(.system(.title2, design: .serif).weight(.semibold))

            // 1. Talk-time ratio.
            VStack(alignment: .leading, spacing: 8) {
                let ratio = stats.teacherTalkRatio
                HStack {
                    Text("Talk-time ratio").font(.headline)
                    Spacer()
                    Text("you spoke \(Int(ratio * 100))% of the time")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(ratio <= 0.15 ? .green : ratio <= 0.30 ? .orange : .red)
                }
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        Rectangle().fill(.red.opacity(0.85))
                            .frame(width: max(geo.size.width * ratio, ratio > 0 ? 3 : 0))
                        Rectangle().fill(.blue.opacity(0.7))
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 12)
                Text(ratio <= 0.15
                     ? "Master range — a Harkness teacher speaks under 10-15% of class."
                     : "Target: under 10-15%. Every word you didn't say, a student had to think.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // 2. Silence & deflections.
            HStack(spacing: 28) {
                statCell(value: stats.silencesHeld, label: "silences held", good: true)
                statCell(value: stats.rescues, label: "silences rescued", good: false)
                statCell(value: stats.deflectionsPassed, label: "deflections passed", good: true)
                statCell(value: stats.deflectionsFailed, label: "lecturing penalties", good: false)
            }

            Divider()

            // 3. Intervention quality.
            VStack(alignment: .leading, spacing: 8) {
                let questions = stats.interventions.filter { $0.move.isQuestionMove }.count
                Text("Intervention quality — \(questions)/\(stats.interventions.count) were questions")
                    .font(.headline)
                if stats.interventions.isEmpty {
                    Text("You never spoke. Pure observation is a move too — but try a tether or a spotlight next run.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(stats.interventions) { intervention in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(intervention.move.label)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(
                                intervention.wasLecturingPenalty ? Color.red.opacity(0.8)
                                : intervention.move.isQuestionMove ? Color.green.opacity(0.7)
                                : Color.gray.opacity(0.5)))
                            .foregroundStyle(.white)
                        Text("“\(intervention.text)”")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            Divider()

            // 4. Table equity.
            VStack(alignment: .leading, spacing: 8) {
                Text("Table equity").font(.headline)
                HStack(spacing: 10) {
                    Image(systemName: debrief.ghostSpoke ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(debrief.ghostSpoke ? .green : .red)
                    Text(debrief.ghostSpoke
                         ? "You drew out the Ghost — Wren spoke \(stats.turnCounts[debrief.ghostID ?? ""] ?? 0) time(s)."
                         : "The Ghost never spoke. Try a direct, safe invitation next time.")
                        .font(.callout)
                }
                let monoShare = debrief.monopolizerShare
                HStack(spacing: 10) {
                    Image(systemName: monoShare <= 0.3 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(monoShare <= 0.3 ? .green : .orange)
                    Text("The Monopolizer took \(Int(monoShare * 100))% of student talk time\(monoShare <= 0.3 ? " — well managed." : " — spotlight others sooner.")")
                        .font(.callout)
                }
                // Per-student share bars.
                ForEach(stats.turnCounts.sorted { $0.value > $1.value }, id: \.key) { id, turns in
                    HStack(spacing: 8) {
                        Text(debrief.studentNames[id] ?? id)
                            .font(.caption)
                            .frame(width: 70, alignment: .leading)
                        GeometryReader { geo in
                            let maxTurns = stats.turnCounts.values.max() ?? 1
                            Capsule().fill(.blue.opacity(0.6))
                                .frame(width: geo.size.width * CGFloat(turns) / CGFloat(max(maxTurns, 1)))
                        }
                        .frame(height: 8)
                        Text("\(turns)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // 5. Guideflow coverage.
            VStack(alignment: .leading, spacing: 8) {
                Text("Guideflow — \(stats.nodesCovered.count)/\(debrief.setup.realizationNodes.count) realizations reached")
                    .font(.headline)
                ForEach(Array(debrief.setup.realizationNodes.enumerated()), id: \.offset) { i, node in
                    HStack(spacing: 8) {
                        Image(systemName: stats.nodesCovered.contains(i + 1) ? "circle.fill" : "circle.dotted")
                            .foregroundStyle(stats.nodesCovered.contains(i + 1) ? .yellow : .secondary)
                        Text(node).font(.callout)
                    }
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.05)))
    }

    private func statCell(value: Int, label: String, good: Bool) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(.title, design: .serif).weight(.bold))
                .foregroundStyle(value == 0 ? Color.secondary : good ? Color.green : Color.red)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview(windowStyle: .automatic) {
    RecapView()
        .environment(AppModel())
}
