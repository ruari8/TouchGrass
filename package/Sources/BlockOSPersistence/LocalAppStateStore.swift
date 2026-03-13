import BlockOSDomain
import Foundation

public struct PersistedAppState: Codable, Sendable {
    public var activeSession: FocusSession?
    public var sessionHistory: [FocusSession]
    public var qrTokens: [QRCodeToken]

    public init(
        activeSession: FocusSession? = nil,
        sessionHistory: [FocusSession] = [],
        qrTokens: [QRCodeToken] = []
    ) {
        self.activeSession = activeSession
        self.sessionHistory = sessionHistory
        self.qrTokens = qrTokens
    }
}

public protocol AppStateStore: Sendable {
    func load() async throws -> PersistedAppState
    func save(_ state: PersistedAppState) async throws
}

public actor InMemoryAppStateStore: AppStateStore {
    private var state: PersistedAppState

    public init(initialState: PersistedAppState = PersistedAppState()) {
        self.state = initialState
    }

    public func load() async throws -> PersistedAppState {
        state
    }

    public func save(_ state: PersistedAppState) async throws {
        self.state = state
    }
}

public actor JSONFileAppStateStore: AppStateStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() async throws -> PersistedAppState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return PersistedAppState()
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(PersistedAppState.self, from: data)
    }

    public func save(_ state: PersistedAppState) async throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}
