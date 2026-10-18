#if os(iOS)
import FamilyControls

public enum ScreenTimeAuthorization {
    public static var isApproved: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    public static func request() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }
}
#endif
