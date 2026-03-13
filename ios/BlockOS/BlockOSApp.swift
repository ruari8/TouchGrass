import SwiftUI
import BlockOSAppSupport
import BlockOSEnforcement
import BlockOSPersistence

@main
struct BlockOSApp: App {
    @StateObject private var container = AppContainer.bootstrap()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
        }
    }
}
