//
//  LoadingView.swift
//  roundtable
//
//  Shown in the window while the immersive classroom builds ("connecting").
//

import SwiftUI

struct LoadingView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ZStack {
            Image("LoadingArt")
                .resizable()
                .scaledToFill()
                .frame(minWidth: 760, minHeight: 640)
                .clipped()
                .overlay(.black.opacity(0.25))

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("Taking your seat…")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(.white)
                if let topic = appModel.sessionConfig?.topic.title {
                    Text(topic)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(28)
            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 22))
        }
        .frame(minWidth: 760, minHeight: 640)
    }
}
