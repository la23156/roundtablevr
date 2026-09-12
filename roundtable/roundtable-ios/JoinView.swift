//
//  JoinView.swift
//  roundtable-ios
//
//  Pre-session screen: SharePlay eligibility, join/activate, and the guest's
//  table identity (name + a character card whose portrait becomes their easel
//  at the Vision Pro table).
//

import GroupActivities
import SwiftUI

struct JoinView: View {
    @Environment(CompanionModel.self) private var model
    @StateObject private var groupStateObserver = GroupStateObserver()

    /// The identity cards a phone guest can pick from (bundled portraits).
    private static let cards: [(id: String, name: String)] = [
        ("elowen", "The Scholar"),
        ("marcus", "The Skeptic"),
        ("zara", "The Dreamer"),
        ("dev", "The Physicist"),
        ("nadia", "The Historian"),
    ]

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    if model.sessionActive {
                        identitySection(name: $model.guestName)
                    } else if groupStateObserver.isEligibleForGroupSession {
                        eligibleSection
                    } else {
                        notEligibleSection
                    }
                }
                .padding(22)
            }
            .navigationTitle("Roundtable")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Join the table")
                .font(.system(.largeTitle, design: .serif).weight(.bold))
            Text("A Vision Pro host runs the seminar; you join from FaceTime, appear on a card at the table, and can speak any time.")
                .font(.system(.callout, design: .serif))
                .foregroundStyle(.secondary)
        }
    }

    private var notEligibleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Start a FaceTime call first", systemImage: "video.fill")
                .font(.headline)
            Text("SharePlay needs an active FaceTime call with the Vision Pro host. Once you're on the call, the Roundtable appears here automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }

    private var eligibleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("FaceTime call detected", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text("Waiting for the host's Roundtable… or start one for the call:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                Task { await model.activate() }
            } label: {
                Label("Open Roundtable in this call", systemImage: "shareplay")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }

    private func identitySection(name: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("\(model.participantCount) at the table", systemImage: "person.2.fill")
                .font(.headline)
                .foregroundStyle(.green)

            Text("Your name at the table")
                .font(.headline)
            TextField("e.g. Latif", text: name)
                .textFieldStyle(.roundedBorder)

            Text("Pick your table card")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Self.cards, id: \.id) { card in
                        identityCard(card)
                    }
                }
                .padding(.vertical, 4)
            }

            Button {
                model.takeSeat()
            } label: {
                Label("Take a seat", systemImage: "chair.lounge.fill")
                    .font(.system(.headline, design: .serif))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func identityCard(_ card: (id: String, name: String)) -> some View {
        let selected = model.chosenCharacterID == card.id
        return VStack(spacing: 6) {
            Group {
                if let image = Self.portrait(card.id) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.brown.opacity(0.4)
                }
            }
            .frame(width: 96, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(card.name)
                .font(.caption.weight(.semibold))
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(selected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .onTapGesture { model.chosenCharacterID = card.id }
    }

    static func portrait(_ id: String) -> UIImage? {
        Bundle.main.url(forResource: id, withExtension: "jpg")
            .flatMap { UIImage(contentsOfFile: $0.path) }
    }
}
