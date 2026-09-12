//
//  SubtitleView.swift
//  roundtable
//
//  Floating caption above the table: who's speaking and what they're saying.
//

import SwiftUI

struct SubtitleView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let subtitle = appModel.sessionController?.subtitle

        Group {
            if let subtitle {
                VStack(spacing: 6) {
                    Text(subtitle.speakerName)
                        .font(.system(.headline, design: .serif).weight(.bold))
                        .foregroundStyle(subtitle.tint)
                    Text(subtitle.text)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 16)
                .frame(maxWidth: 720)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 20))
                .transition(.opacity)
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: subtitle)
    }
}
