import SwiftUI
import TouchGrassCore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.state.hasCompletedSetup {
                TabView {
                    Tab("Home", systemImage: "leaf.fill") {
                        HomeView()
                    }
                    Tab("Rules", systemImage: "slider.horizontal.3") {
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
    }
}
