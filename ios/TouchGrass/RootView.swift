import SwiftUI
import TouchGrassCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = Self.initialTab

    var body: some View {
        @Bindable var model = model
        Group {
            if model.state.hasCompletedSetup {
                TabView(selection: $tab) {
                    Tab("Home", systemImage: "leaf.fill", value: "home") {
                        HomeView()
                    }
                    Tab("Rules", systemImage: "slider.horizontal.3", value: "rules") {
                        RulesView()
                    }
                }
            } else {
                SetupView()
            }
        }
        .sheet(isPresented: $model.isShowingTouchGrass) {
            TouchGrassFlow(mode: .unlock)
        }
        .alert(
            model.ruleChangeNotice ?? "",
            isPresented: Binding(get: { model.ruleChangeNotice != nil }, set: { if !$0 { model.ruleChangeNotice = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    private static var initialTab: String {
        #if DEBUG
        DemoState.initialTab ?? "home"
        #else
        "home"
        #endif
    }
}
