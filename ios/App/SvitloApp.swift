import SwiftUI

@main
struct SvitloApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            GroupsView()
                .environment(model)
                .tint(Theme.fg)
                .task {
                    await model.loadRegions()
                    await model.refresh()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.refresh() } }
                }
                .onOpenURL { model.handle($0) }
        }
    }
}
