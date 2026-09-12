//
//  roundtableApp.swift
//  roundtable
//

import SwiftUI

@main
struct roundtableApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup(id: AppModel.mainWindowID) {
            MainWindowView()
                .environment(appModel)
        }
        .windowResizability(.contentSize)

        ImmersiveSpace(id: AppModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}

/// Routes the single window between menu and recap depending on app phase.
struct MainWindowView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        switch appModel.phase {
        case .menu, .inSession:
            MenuView()
        case .connecting:
            LoadingView()
        case .recap:
            RecapView()
        }
    }
}
