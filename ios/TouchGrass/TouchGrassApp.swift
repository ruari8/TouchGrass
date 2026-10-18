import StoreKit
import SwiftUI
import UserNotifications

@main
struct TouchGrassApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.grass)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                model.refresh()
            }
        }
    }
}

/// Opens the Touch Grass camera when the user taps the notification sent from a shield.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        #if !DEBUG
        // Debug builds already have Developer Settings, and asking for the App Store transaction
        // there prompts for an Apple Account.
        Task { await detectTestFlight() }
        #endif
        return true
    }

    /// TestFlight builds run in the sandbox App Store environment and get Developer Settings.
    private func detectTestFlight() async {
        guard case let .verified(transaction) = try? await AppTransaction.shared else { return }
        if transaction.environment == .sandbox {
            await MainActor.run { AppModel.shared.isDeveloperBuild = true }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.content.userInfo["action"] as? String == "touchGrass" else { return }
        AppModel.shared.isShowingTouchGrass = true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}
