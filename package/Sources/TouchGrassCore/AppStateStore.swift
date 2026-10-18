import Foundation

/// Reads and writes `AppState` as JSON in the App Group.
///
/// The app and its extensions run in separate processes. Every change goes through `update`,
/// which re-reads the file under a file coordinator, writes it, and runs `whileLocked` before
/// letting go, so applying shields for a state can't interleave with another process's change.
public final class AppStateStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = AppGroup.containerURL.appending(path: "state.json")) {
        self.fileURL = fileURL
    }

    public enum StoreError: Error {
        case coordination(Error)
        case unreadable(Error)
        case unwritable(Error)
    }

    public func load() throws -> AppState {
        var result: Result<AppState, Error> = .success(AppState())
        try coordinate(writing: false) { url in
            result = Result { try Self.read(url) }
        }
        return try result.get()
    }

    /// Applies a change to the latest saved state and saves it. If anything throws, nothing is saved
    /// and `whileLocked` doesn't run.
    @discardableResult
    public func update(
        _ change: (inout AppState) throws -> Void,
        whileLocked: (AppState) -> Void = { _ in }
    ) throws -> AppState {
        var result: Result<AppState, Error> = .success(AppState())
        try coordinate(writing: true) { url in
            result = Result {
                var state = try Self.read(url)
                try change(&state)
                try Self.write(state, to: url)
                whileLocked(state)
                return state
            }
        }
        return try result.get()
    }

    private func coordinate(writing: Bool, _ body: (URL) -> Void) throws {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        if writing {
            coordinator.coordinate(writingItemAt: fileURL, options: [], error: &error, byAccessor: body)
        } else {
            coordinator.coordinate(readingItemAt: fileURL, options: [], error: &error, byAccessor: body)
        }
        if let error { throw StoreError.coordination(error) }
    }

    /// A missing file is a fresh install. A file that exists but can't be decoded is an error,
    /// so a later write doesn't silently replace it with an empty state.
    private static func read(_ url: URL) throws -> AppState {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppState() }
        do {
            return try JSONDecoder().decode(AppState.self, from: Data(contentsOf: url))
        } catch {
            throw StoreError.unreadable(error)
        }
    }

    private static func write(_ state: AppState, to url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(state).write(to: url, options: .atomic)
        } catch {
            throw StoreError.unwritable(error)
        }
    }
}
