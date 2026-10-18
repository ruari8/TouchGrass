import Foundation

/// Reads and writes `AppState` as JSON in the App Group.
/// The app and its extensions run in separate processes, so every change goes through `update`,
/// which re-reads the file under a file coordinator before writing.
public final class AppStateStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = AppGroup.containerURL.appending(path: "state.json")) {
        self.fileURL = fileURL
    }

    public func load() -> AppState {
        var state = AppState()
        coordinate(writing: false) { url in
            state = Self.read(url)
        }
        return state
    }

    /// Applies a change to the latest saved state and saves it. If the change throws, nothing is saved.
    @discardableResult
    public func update<E: Error>(_ change: (inout AppState) throws(E) -> Void) throws(E) -> AppState {
        var result = AppState()
        var thrown: E?
        coordinate(writing: true) { url in
            var state = Self.read(url)
            result = state
            do throws(E) {
                try change(&state)
            } catch {
                thrown = error
                return
            }
            try? Self.write(state, to: url)
            result = state
        }
        if let thrown { throw thrown }
        return result
    }

    private func coordinate(writing: Bool, _ body: (URL) -> Void) {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        if writing {
            coordinator.coordinate(writingItemAt: fileURL, options: [], error: &error, byAccessor: body)
        } else {
            coordinator.coordinate(readingItemAt: fileURL, options: [], error: &error, byAccessor: body)
        }
    }

    private static func read(_ url: URL) -> AppState {
        guard let data = try? Data(contentsOf: url) else { return AppState() }
        return (try? JSONDecoder().decode(AppState.self, from: data)) ?? AppState()
    }

    private static func write(_ state: AppState, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
