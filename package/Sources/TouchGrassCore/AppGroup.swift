import Foundation

/// The App Group shared by the app and its Screen Time extensions.
public enum AppGroup {
    public static let identifier = "group.pear.TouchGrass"

    public static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            ?? FileManager.default.temporaryDirectory.appending(path: identifier, directoryHint: .isDirectory)
    }
}
