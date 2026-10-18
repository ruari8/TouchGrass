import ManagedSettings
import UserNotifications

/// Handles the shield's buttons. iOS doesn't let a shield open our app, so "Touch Grass"
/// sends a notification that opens the camera when tapped.
final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler: completionHandler)
    }

    private func respond(to action: ShieldAction, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        guard action == .primaryButtonPressed else {
            completionHandler(.close)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Go touch grass"
        content.body = "Tap here to open the camera."
        content.userInfo = ["action": "touchGrass"]
        let request = UNNotificationRequest(identifier: "touchGrass", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in
            completionHandler(.close)
        }
    }
}
