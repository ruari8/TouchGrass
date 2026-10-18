import Foundation

/// The App Group shared by the app and its Screen Time extensions.
public enum AppGroup {
    public static let identifier = "group.pear.TouchGrass"

    /// The shared container. On iOS a missing container means the entitlements are wrong, and carrying on
    /// would quietly give the app and each extension separate state, so it stops instead.
    public static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        #if os(iOS)
        preconditionFailure("App Group \(identifier) is unavailable. Check the target's entitlements and signing.")
        #else
        return FileManager.default.temporaryDirectory.appending(path: identifier, directoryHint: .isDirectory)
        #endif
    }

    /// Small shared values that aren't part of `AppState`, such as DeviceActivity bookkeeping.
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
